#include "str_util.h"
#include "compat/misc.h"
#include "profile/settings.h"

namespace profile {

SettingCategory::SettingCategory() {
}

SettingCategory::SettingCategory(const std::string& Name) : name(Name) {
}

SettingCategory::~SettingCategory() {
}

Settings::~Settings() {
	foreach(it, categories)
		delete *it;
}

void Settings::clear() {
	foreach(it, categories)
		delete *it;
	categories.clear();
	settings.clear();
}

NamedGeneric* Settings::getSetting(const std::string& name) {
	auto it = settings.find(name);
	if(it == settings.end())
		return 0;
	return it->second;
}

void Settings::loadDescriptors(const std::string& filename) {
	DataReader datafile(filename);
	SettingCategory* cat = 0;
	NamedGeneric* set = 0;
	while(datafile++) {
		if(datafile.key == "Category") {
			cat = new SettingCategory();
			categories.push_back(cat);
			cat->name = datafile.value;
		}
		else if(cat) {
			auto makeSetting = [&](GenericType typevalue) {
				set = new NamedGeneric();
				set->name = datafile.value;
				set->type = typevalue;
				cat->settings.push_back(set);
				settings[set->name] = set;
			};
			
			if(datafile.key == "Bool") {
				makeSetting(GT_Bool);
			}
			else if(datafile.key == "Integer") {
				makeSetting(GT_Integer);
			}
			else if(datafile.key == "Double") {
				makeSetting(GT_Double);
			}
			else if(datafile.key == "Enum") {
				makeSetting(GT_Enum);
				set->values = new std::vector<std::string>();
			}
			else if(datafile.key == "String") {
				makeSetting(GT_String);
				set->str = new std::string();
			}
			else if(set) {
				if(datafile.key == "Default") {
					set->fromString(datafile.value);
				}
				else if(datafile.key == "Option") {
					if(set->type == GT_Enum)
						set->values->push_back(datafile.value);
				}
				else if(datafile.key == "Min") {
					if(set->type == GT_Integer)
						set->num_min = toNumber<int>(datafile.value);
					else if(set->type == GT_Double)
						set->flt_min = toNumber<double>(datafile.value);
				}
				else if(datafile.key == "Max") {
					if(set->type == GT_Integer)
						set->num_max = toNumber<int>(datafile.value);
					else if(set->type == GT_Double)
						set->flt_max = toNumber<double>(datafile.value);
				}
			}
		}
	}
}

void Settings::addCategory(SettingCategory* cat) {
	categories.push_back(cat);
	foreach(it, cat->settings)
		settings[(*it)->name] = (*it);
}

void Settings::loadSettings(const std::string& filename) {
	DataReader datafile(filename);
	while(datafile++) {
		NamedGeneric* set = getSetting(datafile.key);
		if(set)
			set->fromString(datafile.value);
	}
}

void Settings::saveSettings(const std::string& filename) {
	std::ofstream file(filename);

	for(auto iCat = categories.begin(), catEnd = categories.end(); iCat != catEnd; ++iCat) {
		auto* cat = *iCat;
		file << cat->name << "\n";

		for(auto i = cat->settings.begin(), end = cat->settings.end(); i != end; ++i) {
			auto* set = *i;
			file << "\t" << set->name << ": " << set->toString() << "\n";
		}
	}

	file.close();
}
	
};
