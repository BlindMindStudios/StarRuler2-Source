#include "render/render_state.h"
#include "main/references.h"
#include "main/initialization.h"
#include "resource/library.h"
#include "gui/skin.h"
#include "str_util.h"
#include "num_util.h"
#include "compat/misc.h"
#include "main/logging.h"
#include <iostream>
#include <fstream>
#include <string>
#include <unordered_map>
#include <functional>

namespace resource {
	
umap<std::string, DimensionMode> INIT_VAR(dimension_modes) {
	dimension_modes["Uniform"] = DM_Uniform;
	dimension_modes["Scaled"] = DM_Scaled;
	dimension_modes["Tiled"] = DM_Tiled;
} INIT_VAR_END;

umap<std::string, GradientMode> INIT_VAR(gradient_modes) {
	gradient_modes["Normal"] = GM_Normal;
	gradient_modes["Overlay"] = GM_Overlay;
} INIT_VAR_END;

umap<std::string, AspectMarginMode> INIT_VAR(aspect_modes) {
	aspect_modes["Horizontal"] = AMM_Horizontal;
	aspect_modes["Vertical"] = AMM_Vertical;
	aspect_modes["None"] = AMM_None;
} INIT_VAR_END;


void parseElementIdentifier(const std::string& str, int& style, unsigned& flags, bool addIfMissing) {
	std::vector<std::string> args;
	split(str, args, ',');

	flags = 0;
	style = gui::skin::getStyleIndex(trim(args[0]), addIfMissing);

	for(unsigned i = 1; i < args.size(); ++i)
		flags |= gui::skin::getElementFlag(trim(args[i]), addIfMissing);
}

unsigned parseElementFlags(const std::string& str, bool addIfMissing) {
	std::vector<std::string> args;
	split(str, args, ',');

	unsigned flags = 0;
	for(unsigned i = 0; i < args.size(); ++i)
		flags |= gui::skin::getElementFlag(trim(args[i]), addIfMissing);
	return flags;
}

#define HANDLE_RELCOORD(handler, key, obj, member, pos) handler(key, [&](std::string& value) {\
	if(!obj || obj->member.empty())\
		return;\
	\
	auto& pos = obj->member.back().area.pos;\
	\
	if(value[value.size() - 1] == '%') {\
		value = value.substr(0, value.size() - 1);\
		double val = toNumber<double>(value);\
		\
		if(val < 0)\
			pos.set(RPT_Right, 0, -val / 100.0);\
		else\
			pos.set(RPT_Left, 0, val / 100.0);\
	}\
	else {\
		int val = toNumber<int>(value);\
		\
		if(val < 0)\
			pos.set(RPT_Right, -val, 0.0);\
		else\
			pos.set(RPT_Left, val, 0.0);\
	}\
});

#define HANDLE_GCOLOR(handler, key, obj, member, pos) handler(key, [&](std::string& value) {\
	if(!obj || obj->member.empty())\
		return;\
	obj->member.back().pos = toColor(value);\
});

void Library::loadSkins(const std::string& filename) {
	DataHandler datahandler;
	gui::skin::Skin* skin = 0;

	//Handling for the skin styles file
	datahandler("Skin", [&](std::string& value) {
		if(isIdentifier(value)) {
			skin = new gui::skin::Skin();
			skins[value] = skin;
		}
		else {
			skin = 0;
			error("Skin '%s' is not a valid identifier", value.c_str());
		}
	});

	datahandler("Material", [&](std::string& value) {
		if(!skin)
			return;
		skin->materialName = value;
	});

	datahandler("File", [&](std::string& value) {
		if(!skin)
			return;
		std::string filename = devices.mods.resolve(value);
		loadSkin(filename, skin);
		skin_files[filename] = skin;

		if(watch_resources)
			watchSkin(filename);
	});

	datahandler.read(filename);
}

void Library::loadSkin(const std::string& filename, gui::skin::Skin* skin) {
	DataHandler skinhandler;
	gui::skin::Element* ele = 0;
	gui::skin::Style* style = 0;

	//Handling for global skin stuff
	skinhandler("Color", [&](std::string& value) {
		std::vector<std::string> args;
		split(value, args, '=');

		if(args.size() != 2)
			return;

		unsigned index = gui::skin::getColorIndex(trim(args[0]), true);
		skin->setColor(index, toColor(trim(args[1])));
	});

	skinhandler("Font", [&](std::string& value) {
		std::vector<std::string> args;
		split(value, args, '=');

		if(args.size() != 2)
			return;

		unsigned index = gui::skin::getFontIndex(trim(args[0]), true);
		skin->setFont(index, &getFont(trim(args[1])));
	});

	//Handling for styles and elements
	skinhandler("Style", [&](std::string& value) {
		if(!isIdentifier(value)) {
			style = 0;
			error("Style '%s' is not a valid identifier", value.c_str());
			return;
		}

		unsigned index = gui::skin::getStyleIndex(value, true);
		if(!skin->hasStyle(index)) {
			style = new gui::skin::Style();
			skin->setStyle(index, style);
		}
		else {
			style = (gui::skin::Style*)&skin->getStyle(index);
		}
		ele = 0;
	});

	skinhandler("Element", [&](std::string& value) {
		unsigned flags = parseElementFlags(value, true);

		if(style) {
			ele = style->getExactElement(flags);
			if(!ele) {
				ele = new gui::skin::Element();
				ele->flags = flags;
				ele->material = skin->material;
				style->addElement(ele);
			}
			else {
				ele->clear();
			}
		}
		else {
			ele = new gui::skin::Element();
			ele->flags = flags;
		}
	});

	skinhandler("Shape", [&](std::string& value) {
		if(!style)
			return;

		if(value == "Regular")
			style->irregular = false;
		else
			style->irregular = true;
	});

	skinhandler("Inherit", [&](std::string& value) {
		if(!style)
			return;

		if(ele) {
			unsigned oldFlags = ele->flags;

			int style;
			unsigned flags;
			parseElementIdentifier(value, style, flags, false);
			if(style == -1)
				return;

			*ele = skin->getElement(style, flags);
			ele->flags = oldFlags;
		}
		else {
			int styleID;
			unsigned flags;
			parseElementIdentifier(value, styleID, flags, false);
			if(styleID == -1)
				return;

			const gui::skin::Style& old = skin->getStyle(styleID);
			style->irregular = old.irregular;
			foreach(it, old.elements) {
				ele = new gui::skin::Element();
				*ele = **it;
				style->addElement(ele);
			}
			ele = 0;
		}
	});

	skinhandler("Rect", [&](std::string& value) {
		if(!ele)
			return;

		sscanf(value.c_str(), " [ %i , %i ] [ %i , %i ]", &ele->area.topLeft.x,
			&ele->area.topLeft.y, &ele->area.botRight.x, &ele->area.botRight.y);
	});

	HANDLE_ENUM(skinhandler, "Horizontal", ele, horizMode, dimension_modes);
	HANDLE_ENUM(skinhandler, "Vertical", ele, vertMode, dimension_modes);
	HANDLE_ENUM(skinhandler, "AspectMargin", ele, aspectMargin, aspect_modes);
	HANDLE_ENUM(skinhandler, "GradientMode", ele, gradMode, gradient_modes);

	HANDLE_BOOL(skinhandler, "Filled", ele, filled);
	skinhandler("Margin", [&](std::string& value) {
		std::vector<std::string> numbers;
		split(value, numbers, ',', true);

		if(numbers.size() == 4) {
			ele->margin = recti(
				toNumber<int>(numbers[0]),
				toNumber<int>(numbers[1]),
				toNumber<int>(numbers[2]),
				toNumber<int>(numbers[3]));
		}
		else if(numbers.size() == 2) {
			int x = toNumber<int>(numbers[0]);
			int y = toNumber<int>(numbers[1]);
			ele->margin = recti(x, y, x, y);
		}
		else if(numbers.size() == 1) {
			int num = toNumber<int>(numbers[0]);
			ele->margin = recti(num, num, num, num);
		}
		else {
			error("Margin specifier '%s' invalid.", value.c_str());
		}
	});

	//Handling for gradients
	skinhandler("Add Gradient", [&](std::string& value) {
		ele->gradients.push_back(gui::skin::Gradient());
	});

	HANDLE_RELCOORD(skinhandler, "GX1", ele, gradients, left);
	HANDLE_RELCOORD(skinhandler, "GY1", ele, gradients, top);
	HANDLE_RELCOORD(skinhandler, "GX2", ele, gradients, right);
	HANDLE_RELCOORD(skinhandler, "GY2", ele, gradients, bottom);

	HANDLE_GCOLOR(skinhandler, "TopLeft", ele, gradients, colors[0]);
	HANDLE_GCOLOR(skinhandler, "TopRight", ele, gradients, colors[1]);
	HANDLE_GCOLOR(skinhandler, "BotLeft", ele, gradients, colors[2]);
	HANDLE_GCOLOR(skinhandler, "BotRight", ele, gradients, colors[3]);

	//Handling for layers
	skinhandler("Layer", [&](std::string& value) {
		if(!ele)
			return;

		int style;
		unsigned flags;
		parseElementIdentifier(value, style, flags, false);
		if(style == -1)
			return;

		ele->layers.push_back(gui::skin::Layer());
		ele->layers.back().ele = &skin->getElement(style, flags);
	});

	HANDLE_RELCOORD(skinhandler, "OX1", ele, layers, left);
	HANDLE_RELCOORD(skinhandler, "OY1", ele, layers, top);
	HANDLE_RELCOORD(skinhandler, "OX2", ele, layers, right);
	HANDLE_RELCOORD(skinhandler, "OY2", ele, layers, bottom);

	skinhandler("Color Override", [&](std::string& value) {
		if(!ele)
			return;
		if(ele->layers.size() == 0)
			return;

		ele->layers.back().hasOverride = true;
		ele->layers.back().override = toColor(value);
	});

	//Read styles file
	skinhandler.read(filename);
}

void Library::bindSkinMaterials() {
	foreach(it, skins) {
		const render::RenderState& mat = getMaterial(it->second->materialName);
		it->second->material = &mat;

		foreach(style, it->second->styles) {
			if(*style) {
				foreach(ele, (*style)->elements) {
					(*ele)->material = &mat;
				}
			}
		}
	}
}

};
