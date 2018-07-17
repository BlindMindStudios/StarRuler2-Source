#pragma once
#include "compat/misc.h"
#include <string>
#include <unordered_map>

namespace resource {

class Locale {
public:
	umap<std::string, std::string*> localizations;
	umap<std::string, std::string*> hashLocalizations;

	void clear();
	void load(const std::string& filename);

	std::string localize(const std::string& text, bool requireHash = false, bool doUnescape = true, bool doFormat = true);
	~Locale();
};

};
