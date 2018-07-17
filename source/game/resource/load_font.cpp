#include "main/references.h"
#include "resource/library.h"
#include "main/logging.h"
#include "str_util.h"
#include "num_util.h"
#include "main/tick.h"
#include "render/font.h"
#include <iostream>
#include <fstream>
#include <string>

namespace resource {

void Library::loadFonts(const std::string& filename) {
	std::string font_name, font_file, font_locale;
	std::vector<std::pair<int,int>> pages;
	std::vector<std::string> replaces;
	int size = 12;
	render::Font* bold = 0;
	render::Font* italic = 0;

	auto makeFont = [&]() {
		if(font_name.empty() || font_file.empty())
			return;
		if(font_locale.empty() || font_locale == game_locale) {
			render::Font* font = 0;
			auto p_ext = strrchr(font_file.c_str(), '.');
			if(!p_ext || strcmp_nocase(p_ext, ".fnt") == 0)
				font = render::loadFontFNT(devices.render, font_file.c_str());
			else if(strcmp_nocase(p_ext, ".ttf") == 0)
				font = render::loadFontFT2(*devices.render, font_file.c_str(), pages, size);
			else if(strcmp_nocase(p_ext, ".otf") == 0)
				font = render::loadFontFT2(*devices.render, font_file.c_str(), pages, size);
			else
				error("Font file '%s' in unrecognized format.", font_file.c_str());

			if(font) {
				font->bold = bold;
				font->italic = italic;
				fonts[font_name] = font;
				font_list.push_back(font);

				foreach(it, replaces)
					fonts[*it] = font;
			}
		}

		font_name.clear();
		font_file.clear();
		font_locale.clear();
		replaces.clear();
	};

	DataHandler datahandler;
	datahandler("Font", [&](std::string& value) {
		makeFont();
		font_name = value;
		bold = 0;
		italic = 0;
		pages.clear();
		size = 12;
	});

	datahandler("File", [&](std::string& value) {
		font_file = devices.mods.resolve(value);
	});

	datahandler("Locale", [&](std::string& value) {
		font_locale = value;
	});

	datahandler("Replace", [&](std::string& value) {
		replaces.push_back(value);
	});

	datahandler("Size", [&](std::string& value) {
		size = toNumber<int>(value);
	});

	datahandler("Bold", [&](std::string& value) {
		auto it = fonts.find(value);
		if(it != fonts.end()) {
			bold = it->second;
		}
		else {
			error("Font '%s' does not exist.", value.c_str());
		}
	});

	datahandler("Italic", [&](std::string& value) {
		auto it = fonts.find(value);
		if(it != fonts.end()) {
			italic = it->second;
		}
		else {
			error("Font '%s' does not exist.", value.c_str());
		}
	});

	datahandler.defaultHandler([&](std::string& key, std::string& value) {
		if(key.compare(0, 4, "Page") == 0) {
			std::vector<std::string> numbers;
			split(value, numbers, '-');

			if(numbers.size() == 2)
				pages.push_back(std::pair<int,int>(toNumber<int>(numbers[0], 0, std::hex),
												   toNumber<int>(numbers[1], 255, std::hex)));
		}
	});

	datahandler.read(filename);
	makeFont();
}

};
