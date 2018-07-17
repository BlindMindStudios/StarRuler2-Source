#include "empire.h"
#include "str_util.h"

#include <string>
#include <unordered_map>

static unsigned nextIndex = 0;
std::unordered_map<std::string,unsigned> statIndices;
static std::unordered_map<unsigned,std::string> indexNames;

struct StatType {
	bool isInt;

	StatType() : isInt(true) {}
};

static std::vector<StatType> types;

unsigned getEmpireStatCount() {
	return (unsigned)statIndices.size();
}

std::string getEmpireStatName(unsigned id) {
	auto iter = indexNames.find(id);
	if(iter != indexNames.end())
		return iter->second;
	else
		return "<invalid>";
}

unsigned getStatID(const std::string& name) {
	auto iter = statIndices.find(name);
	if(iter != statIndices.end())
		return iter->second;
	else
		return 0xffffffff;
}

bool statIsint(unsigned id) {
	if(id < types.size())
		return types[id].isInt;
	else
		return false;
}

void clearEmpireStats() {
	nextIndex = 0;
	statIndices.clear();
	indexNames.clear();
	types.clear();
}

void loadEmpireStats(const std::string& filename) {
	DataHandler data;

	data("Stat", [&](std::string& value) {
		unsigned index = nextIndex++;
		statIndices[value] = index;
		indexNames[index] = value;
		types.push_back(StatType());
	});

	data("Type", [&](std::string& value) {
		if(statIndices.empty())
			return;

		if(streq_nocase(value, "integer"))
			types.back().isInt = true;
		else if(streq_nocase(value, "float"))
			types.back().isInt = false;
	});

	data.read(filename);
}