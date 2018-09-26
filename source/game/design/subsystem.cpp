#include "design/subsystem.h"
#include "design/design.h"
#include "design/hull.h"
#include "main/initialization.h"
#include "main/references.h"
#include "network/network_manager.h"
#include "main/logging.h"
#include "scripts/manager.h"
#include "str_util.h"
#include "util/format.h"
#include "util/save_file.h"
#include "threads.h"
#include "compat/misc.h"
#include "empire.h"
#include "obj/blueprint.h"
#include <algorithm>
#include <unordered_map>
#include <queue>

std::vector<SubsystemDef*> subsystems;
umap<std::string, int> subsystemIndices;
umap<std::string, int> variableIndices;
umap<std::string, int> hexVariableIndices;
umap<std::string, int> shipVariableIndices;
umap<std::string, int> numericTags;
asIScriptFunction* Subsystem::ScriptInitFunction;
asIScriptFunction* Subsystem::ScriptHookFunctions[EH_COUNT];

std::vector<SubsystemDef::ModuleDesc*> ModulesByID;
std::vector<SubsystemDef::ModifyStage*> ModifiersByID;

int getSubsystemDefCount() {
	return (int)subsystems.size();
}

void enumerateVariables(std::function<void(const std::string&,int)> cb) {
	foreach(it, variableIndices)
		cb(it->first, it->second);
}

void enumerateHexVariables(std::function<void(const std::string&,int)> cb) {
	foreach(it, hexVariableIndices)
		cb(it->first, it->second);
}

void enumerateShipVariables(std::function<void(const std::string&,int)> cb) {
	foreach(it, shipVariableIndices)
		cb(it->first, it->second);
}

void enumerateSysTags(std::function<void(const std::string&,int)> cb) {
	foreach(it, numericTags)
		cb(it->first, it->second);
}

const SubsystemDef* getSubsystemDef(const std::string& name) {
	auto it = subsystemIndices.find(name);
	if(it == subsystemIndices.end())
		return 0;
	return subsystems[it->second];
}

const SubsystemDef* getSubsystemDef(int id) {
	if(id < 0 || id >= (int)subsystems.size())
		return 0;
	return subsystems[id];
}

int getVariableIndex(const std::string& name) {
	auto it = variableIndices.find(name);
	if(it == variableIndices.end())
		return -1;
	return it->second;
}

int getHexVariableIndex(const std::string& name) {
	auto it = hexVariableIndices.find(name);
	if(it == hexVariableIndices.end())
		return -1;
	return it->second;
}

unsigned getShipVariableCount() {
	return (unsigned)shipVariableIndices.size();
}

int getShipVariableIndex(const std::string& name) {
	auto it = shipVariableIndices.find(name);
	if(it == shipVariableIndices.end())
		return -1;
	return it->second;
}

int getSysTagIndex(const std::string& name, bool create) {
	auto it = numericTags.find(name);
	if(it == numericTags.end()) {
		if(create) {
			unsigned index = numericTags.size();
			numericTags[name] = index;
			return index;
		}
		return -1;
	}
	return it->second;
}

const std::string errStr = "N/A";
const std::string& getVariableId(int index) {
	//TODO: Make not slow
	foreach(it, variableIndices) {
		if(it->second == index)
			return it->first;
	}
	return errStr;
}

const std::string& getHexVariableId(int index) {
	//TODO: Make not slow
	foreach(it, hexVariableIndices) {
		if(it->second == index)
			return it->first;
	}
	return errStr;
}

const std::string& getShipVariableId(int index) {
	//TODO: Make not slow
	foreach(it, shipVariableIndices) {
		if(it->second == index)
			return it->first;
	}
	return errStr;
}

enum VariableType {
	VTF_BaseVariable =     1 << 31,
	VT_ConstantVariable =  0 << 24,
	VT_SubsystemVariable = 1 << 24,
	VT_HexVariable =       2 << 24,
	VT_ModuleCount =       3 << 24,
	VT_ModuleExists =      4 << 24,
	VT_Argument =          5 << 24,
	VT_ShipVariable =      6 << 24,
	VT_GameConfig =        7 << 24,
	VT_SumVariable =       8 << 24,
	VT_HexSumVariable =    9 << 24,
	VT_TagCountVariable =  10 << 24,
	VT_AdjacentTag      =  11 << 24,
	VT_AdjacentSubsystem = 12 << 24,
};

enum ConstantVariable { //:P
	CV_Hexes,
	CV_InteriorHexes,
	CV_ExteriorHexes,
	CV_HexSize,
	CV_HexExterior,
	CV_ShipSize,
	CV_ShipTotalHexes,
	CV_ShipUsedHexes,
	CV_ShipEmptyHexes,
	CV_AdjacentActive,
	CV_AdjacentThis,
	CV_IsCore,
};

Threaded(const SubsystemDef*) formulaSubsystem = 0;
Threaded(const SubsystemDef::ModifyStage*) formulaModifier = 0;
Threaded(bool) formulaQuiet = false;

static int formulaVarIndex(const std::string* nameptr) {
	std::string name = *nameptr;

	//Arguments
	if(formulaModifier) {
		auto it = formulaModifier->argumentNames.find(name);
		if(it != formulaModifier->argumentNames.end())
			return VT_Argument | it->second;
	}

	//Constant variables
	if(name == "Hexes")
		return VT_ConstantVariable | CV_Hexes;
	else if(name == "InteriorHexes")
		return VT_ConstantVariable | CV_InteriorHexes;
	else if(name == "ExteriorHexes")
		return VT_ConstantVariable | CV_ExteriorHexes;
	else if(name == "HexSize")
		return VT_ShipVariable | ShV_HexSize;
	else if(name == "ShipSize")
		return VT_ConstantVariable | CV_ShipSize;
	else if(name == "ShipUsedHexes")
		return VT_ConstantVariable | CV_ShipUsedHexes;
	else if(name == "ShipTotalHexes")
		return VT_ConstantVariable | CV_ShipTotalHexes;
	else if(name == "ShipEmptyHexes")
		return VT_ConstantVariable | CV_ShipEmptyHexes;
	else if(name == "IsCore")
		return VT_ConstantVariable | CV_IsCore;

	//Game configuration
	if(name[0] == '$') {
		auto it = gameConfig.indices.find(name.substr(1));
		if(it != gameConfig.indices.end())
			return VT_GameConfig | (int)it->second;
	}

	unsigned flags = 0;
	if(name.compare(0, 6, "Base::") == 0) {
		flags |= VTF_BaseVariable;
		name = name.substr(6);
	}

	if(name.find('.') != std::string::npos) {
		//Hex variables
		if(name.compare(0, 4, "Hex.") == 0) {
			//Constant hex variables
			std::string varname = name.substr(4, name.size() - 4);
			if(varname == "Exterior")
				return VT_ConstantVariable | CV_HexExterior;

			//Hex formula variables
			int i = getHexVariableIndex(varname);
			if(i < 0) {
				if(!formulaQuiet)
					error("Error: Formula: Invalid variable '%s'.", name.c_str());
				return -1;
			}

			if(formulaSubsystem) {
				if(i >= (int)formulaSubsystem->hexVariableIndices.size() ||
					formulaSubsystem->hexVariableIndices[i] < 0) {
					if(!formulaQuiet)
						error("Error: Formula: Subsystem '%s' does not have variable '%s'.",
							formulaSubsystem->id.c_str(), name.c_str());
					return -1;
				}
			}

			return VT_HexVariable | flags | i;
		}

		if(name.compare(0, 9, "Adjacent.") == 0) {
			//Constant hex variables
			std::string varname = name.substr(9, name.size() - 9);
			if(varname == "Active")
				return VT_ConstantVariable | CV_AdjacentActive;
			if(varname == "This")
				return VT_ConstantVariable | CV_AdjacentThis;

			//Tags
			if(varname.compare(0, 4, "Tag.")) {
				int i = getSysTagIndex(varname.substr(4, varname.size()-4));
				if(i < 0) {
					if(!formulaQuiet)
						error("Error: Formula: Invalid tag '%s'.", name.c_str());
					return -1;
				}

				return VT_AdjacentTag | i;
			}

			//Subsystems
			const SubsystemDef* def = getSubsystemDef(varname);
			if(def != nullptr)
				return VT_AdjacentSubsystem | def->index;
		}

		//Ship variables
		if(name.compare(0, 5, "Ship.") == 0) {
			//Constant hex variables
			std::string varname = name.substr(5, name.size() - 5);

			//Ship formula variables
			int i = getShipVariableIndex(varname);
			if(i < 0) {
				if(!formulaQuiet)
					error("Error: Formula: Invalid variable '%s'.", name.c_str());
				return -1;
			}

			return VT_ShipVariable | flags | i;
		}

		//Sum variables
		if(name.compare(0, 4, "Sum.") == 0) {
			//Constant hex variables
			std::string varname = name.substr(4, name.size() - 4);

			//Ship formula variables
			int i = getVariableIndex(varname);
			if(i < 0) {
				if(!formulaQuiet)
					error("Error: Formula: Invalid variable for sum '%s'.", name.c_str());
				return -1;
			}

			return VT_SumVariable | flags | i;
		}

		//Hex sum variables
		if(name.compare(0, 7, "HexSum.") == 0) {
			//Constant hex variables
			std::string varname = name.substr(7, name.size() - 7);

			//Hex formula variables
			int i = getHexVariableIndex(varname);
			if(i < 0) {
				if(!formulaQuiet)
					error("Error: Formula: Invalid variable '%s'.", name.c_str());
				return -1;
			}

			return VT_HexSumVariable | flags | i;
		}

		//Tag count variable
		if(name.compare(0, 9, "TagCount.") == 0) {
			std::string varname = name.substr(9, name.size() - 9);

			int i = getSysTagIndex(varname);
			if(i < 0) {
				if(!formulaQuiet)
					error("Error: Formula: Invalid tag '%s'.", name.c_str());
				return -1;
			}

			return VT_TagCountVariable | i;
		}

		//Module metavariables
		if(formulaSubsystem) {
			for(unsigned i = 0, cnt = (unsigned)formulaSubsystem->modules.size(); i < cnt; ++i) {
				SubsystemDef::ModuleDesc& mod = *formulaSubsystem->modules[i];
				if(name.size() <= mod.id.size() + 1)
					continue;
				if(name.compare(0, mod.id.size(), mod.id)) {
					size_t pos = mod.id.size();
					if(name[pos] == '.') {
						if(name.compare(pos + 1, name.size() - pos - 1, "Count")) {
							return VT_ModuleCount | i;
						}
						else if(name.compare(pos + 1, name.size() - pos - 1, "Exists")) {
							return VT_ModuleExists | i;
						}
					}
				}
			}
		}
	}

	//Subsystem variables
	int i = getVariableIndex(name);
	if(i < 0) {
		if(!formulaQuiet)
			error("Error: Formula: Invalid variable '%s'.\n", name.c_str());
		return -1;
	}

	if(formulaSubsystem) {
		if(i >= (int)formulaSubsystem->variableIndices.size() ||
			formulaSubsystem->variableIndices[i] < 0) {
			if(!formulaQuiet)
				error("Error: Formula: Subsystem '%s' does not have variable '%s'.",
					formulaSubsystem->id.c_str(), name.c_str());
			return -1;
		}
	}

	return VT_SubsystemVariable | flags | i;
}

Formula* parseFormula(const std::string& str, const SubsystemDef* def, const SubsystemDef::ModifyStage* modifier) {
	formulaSubsystem = def;
	formulaModifier = modifier;

	Formula* f = Formula::fromInfix(str.c_str(), formulaVarIndex);

	formulaModifier = 0;
	formulaSubsystem = 0;

	return f;
}

int SV_Size = -1, HV_Resistance = -1, HV_HP = -1, ShV_HexSize = -1;

struct TemplateBlock {
	std::vector<std::pair<int,std::string>> conditions;
	std::vector<std::string> lines;
};

bool conditionMatches(const SubsystemDef* cur, std::vector<std::pair<int,std::string>>& conditions) {
	bool passesAll = true;
	foreach(c, conditions) {
		int type = c->first;
		bool negation = false;
		if(type & TC_NOT) {
			type &= ~TC_NOT;
			negation = true;
		}

		bool pass = true;
		switch(type) {
			case TC_Tag:
				if(!cur->hasTag(c->second))
					pass = false;
			break;
			case TC_Modifier:
				if(cur->modifierIds.find(c->second) == cur->modifierIds.end())
					pass = false;
			break;
			case TC_Variable: {
				int globalIndex = getVariableIndex(c->second);
				if(globalIndex < 0) {
					pass = false;
				}
				else {
					if((unsigned)globalIndex >= cur->variableIndices.size()) {
						pass = false;
					}
					else if(cur->variableIndices[globalIndex] < 0) {
						pass = false;
					}
				}
			} break;
			case TC_HexVariable: {
				int globalIndex = getHexVariableIndex(c->second);
				if(globalIndex < 0) {
					pass = false;
				}
				else {
					if((unsigned)globalIndex >= cur->hexVariableIndices.size()) {
						pass = false;
					}
					else if(cur->hexVariableIndices[globalIndex] < 0) {
						pass = false;
					}
				}
			} break;
			case TC_ShipVariable: {
				int globalIndex = getShipVariableIndex(c->second);
				if(globalIndex < 0) {
					pass = false;
				}
				else {
					if((unsigned)globalIndex >= cur->shipVariableIndices.size()) {
						pass = false;
					}
					else if(cur->shipVariableIndices[globalIndex] < 0) {
						pass = false;
					}
				}
			} break;
			case TC_Subsystem: {
				pass = cur->id == c->second;
			} break;
		}

		if(!negation) {
			if(!pass)
				passesAll = false;
		}
		else {
			if(pass)
				passesAll = false;
		}
	}
	return passesAll;
}

void parseConditions(const std::string& value, std::vector<std::pair<int,std::string>>& conditions) {
	std::vector<std::string> conds;
	split(value, conds, ',', true);

	foreach(it, conds) {
		std::vector<std::string> parts;
		split(*it, parts, '/', true);

		std::string value;
		int cond = 0;
		if(parts[0][0] == '!') {
			parts[0] = parts[0].substr(1);
			cond = TC_NOT;
		}
		if(parts.size() == 2) {
			value = parts[1];
			if(parts[0] == "tag") {
				cond |= TC_Tag;
			}
			else if(parts[0] == "mod") {
				cond |= TC_Modifier;
			}
			else if(parts[0] == "var") {
				cond |= TC_Variable;
			}
			else if(parts[0] == "hexVar") {
				cond |= TC_HexVariable;
			}
			else if(parts[0] == "shipVar") {
				cond |= TC_ShipVariable;
			}
			else {
				error("  Invalid condition: %s", it->c_str());
				continue;
			}
		}
		else {
			cond |= TC_Subsystem;
			value = parts[0];
		}

		conditions.push_back(
			std::pair<int,std::string>(
				cond, value));
	}
}

void parseShipModifier(SubsystemDef::ShipModifier& mod, const std::string& value) {
	std::string conds;
	std::string func;

	//Separate conditions
	auto sep = value.find("::");
	if(sep != std::string::npos) {
		conds = value.substr(0,sep);
		func = value.substr(sep+2);
	}
	else {
		func = value;
	}

	parseConditions(conds, mod.conditions);

	//Check if we have any arguments
	std::vector<std::string> args;
	std::string name;
	if(funcSplit(func, name, args)) {
		mod.modifyName = name;
		for(size_t i = 0, cnt = args.size(); i < cnt && i < MODIFY_STAGE_MAXARGS; ++i)
			mod.str_arguments.push_back(args[i]);
	}
	else {
		mod.modifyName = func;
	}
}

DataHandler* sysHandler = 0;
static SubsystemDef* def = 0;
static SubsystemDef::ModuleDesc* mod = 0;
static SubsystemDef::ModifyStage* stage = 0;
static SubsystemDef::Effect* eff = 0;
static SubsystemDef::Effector* efftr = 0;
static SubsystemDef::Assert* ass = 0;
static std::vector<TemplateBlock*> templates;
static TemplateBlock* temp = 0;
static bool inTemplate = false;
static int modStage = 1;
static int overrideHexArcLimitTag = -1;

void clearSubsystemDefinitions() {
	foreach(it, subsystems)
		delete *it;
	subsystems.clear();
	subsystemIndices.clear();
	variableIndices.clear();
	numericTags.clear();

	foreach(it, templates)
		delete *it;
	templates.clear();
	def = 0;
	mod = 0;
	stage = 0;
	eff = 0;
	efftr = 0;
	ass = 0;
	temp = 0;
	inTemplate = false;
	modStage = 1;
	ModulesByID.clear();
	ModifiersByID.clear();
}

void loadSubsystemDefinitions(const std::string& filename) {
	modStage = 1;
	def = 0;
	mod = 0;
	stage = 0;
	eff = 0;
	efftr = 0;
	ass = 0;
	temp = 0;
	inTemplate = false;

	overrideHexArcLimitTag = getSysTagIndex("OverrideHexArcLimit", true);

	if(sysHandler != 0) {
		sysHandler->read(filename);
		SV_Size = getVariableIndex("Size");
		HV_Resistance = getHexVariableIndex("Resistance");
		HV_HP = getHexVariableIndex("HP");
		ShV_HexSize = getShipVariableIndex("HexSize");
		return;
	}

	sysHandler = new DataHandler();
	DataHandler& handler = *sysHandler;
	handler.defaultHandler([&](std::string& key, std::string& value) {
		error(handler.position());
		error("  Invalid line format.");
	});

	{
		auto& templateBlock = handler.block("Template");
		templateBlock.openBlock([&](std::string& value) -> bool {
			temp = new TemplateBlock();
			templates.push_back(temp);
			parseConditions(value, temp->conditions);
			return true;
		});

		templateBlock.lineHandler([&](std::string& line) {
			temp->lines.push_back(line);
		});
	}
	{
		auto& subsysBlock = handler.block("Subsystem");
		subsysBlock.openBlock([&](std::string& id) -> bool {
			def = new SubsystemDef();
			def->index = (int)subsystems.size();
			def->id = id;
			def->variableIndices.resize(variableIndices.size());
			modStage = 1;

			for(unsigned i = 0; i < def->variableIndices.size(); ++i)
				def->variableIndices[i] = -1;

			subsystems.push_back(def);
			subsystemIndices[id] = def->index;
			return true;
		});

		subsysBlock.closeBlock([&]() {
			def = 0;
		});

		auto getVariable = [&](std::string& name) -> SubsystemDef::Variable& {
			bool dependent = false;
			if(name.compare(0, 4, "out ") == 0) {
				name = name.substr(4);
				dependent = true;
			}

			//Check if it is a hex variable
			if(name.compare(0, 4, "Hex.") == 0) {
				//Remove hex part
				name = name.substr(4, name.size() - 4);

				//Find global index
				int index;
				auto it = hexVariableIndices.find(name);
				if(it == hexVariableIndices.end()) {
					index = (int)hexVariableIndices.size();
					hexVariableIndices[name] = index;
				}
				else {
					index = it->second;
				}

				//Check if we have the variable
				if((int)def->hexVariableIndices.size() <= index) {
					int prevLen = (int)def->hexVariableIndices.size();
					def->hexVariableIndices.resize(index + 1);
					for(int i = prevLen; i <= index; ++i)
						def->hexVariableIndices[i] = -1;
				}
				else {
					if(def->hexVariableIndices[index] != -1) {
						return def->hexVariables[def->hexVariableIndices[index]];
					}
				}
				def->hexVariableIndices[index] = (int)def->hexVariables.size();

				SubsystemDef::Variable var;
				var.name = name;
				var.index = index;
				var.formula = 0;
				var.type = SVT_HexVariable;
				var.dependent = dependent;

				def->hexVariables.push_back(var);
				return def->hexVariables.back();
			}
			//Check if it is a ship variable
			else if(name.compare(0, 5, "Ship.") == 0) {
				//Remove hex part
				name = name.substr(5, name.size() - 5);

				//Find global index
				int index;
				auto it = shipVariableIndices.find(name);
				if(it == shipVariableIndices.end()) {
					index = (int)shipVariableIndices.size();
					shipVariableIndices[name] = index;
				}
				else {
					index = it->second;
				}

				//Check if we have the variable
				if((int)def->shipVariableIndices.size() <= index) {
					int prevLen = def->shipVariableIndices.size();
					def->shipVariableIndices.resize(index + 1);
					for(int i = prevLen; i <= index; ++i)
						def->shipVariableIndices[i] = -1;
				}
				else {
					if(def->shipVariableIndices[index] != -1) {
						return def->shipVariables[def->shipVariableIndices[index]];
					}
				}
				def->shipVariableIndices[index] = def->shipVariables.size();

				SubsystemDef::Variable var;
				var.name = name;
				var.index = index;
				var.formula = 0;
				var.type = SVT_ShipVariable;
				var.dependent = dependent;

				def->shipVariables.push_back(var);
				return def->shipVariables.back();
			}
			else {
				//Find global index
				int index;
				auto it = variableIndices.find(name);
				if(it == variableIndices.end()) {
					index = variableIndices.size();
					variableIndices[name] = index;
				}
				else {
					index = it->second;
				}

				//Check if we have the variable
				if((int)def->variableIndices.size() <= index) {
					int prevLen = def->variableIndices.size();
					def->variableIndices.resize(index + 1);
					for(int i = prevLen; i <= index; ++i)
						def->variableIndices[i] = -1;
				}
				else {
					if(def->variableIndices[index] != -1) {
						return def->variables[def->variableIndices[index]];
					}
				}
				def->variableIndices[index] = def->variables.size();

				SubsystemDef::Variable var;
				var.name = name;
				var.index = index;
				var.formula = 0;
				var.type = SVT_SubsystemVariable;
				var.dependent = dependent;

				def->variables.push_back(var);
				return def->variables.back();
			}
		};

		subsysBlock("Name", [&](std::string& value) {
			def->name = devices.locale.localize(value);
		});

		subsysBlock("BaseColor", [&](std::string& value) {
			def->baseColor = toColor(value);
		});

		subsysBlock("TypeColor", [&](std::string& value) {
			def->typeColor = toColor(value);
		});

		subsysBlock("Elevation", [&](std::string& value) {
			def->elevation = toNumber<int>(value);
		});

		subsysBlock("Description", [&](std::string& value) {
			def->description = devices.locale.localize(value);
		});

		subsysBlock("Picture", [&](std::string& value) {
			def->picMat = value;
		});

		auto addTags = [&](std::vector<std::string>& tags) {
			foreach(t, tags) {
				std::string tag, value;
				auto pos = t->find(':');
				if(pos != std::string::npos) {
					tag = t->substr(0, pos);
					if(pos < t->size()-1)
						value = t->substr(pos+1);
				}
				else {
					tag = *t;
				}

				def->tags.insert(tag);

				auto it = numericTags.find(tag);
				int index = -1;
				if(it != numericTags.end()) {
					index = it->second;
				}
				else {
					index = numericTags.size();
					numericTags[tag] = index;
				}

				def->numTags.insert(index);
				if(!value.empty())
					def->tagValues[index].push_back(value);
			}
		};

		subsysBlock("Tags", [&](std::string& value) {
			std::vector<std::string> tags;
			split(value, tags, ',', true);

			addTags(tags);

			def->isContiguous = def->tags.find("NonContiguous") == def->tags.end();
			def->hasCore = def->tags.find("NoCore") == def->tags.end();
			def->alwaysTakeDamage = def->tags.find("AlwaysTakeDamage") != def->tags.end();
			def->hexLimitArc = def->tags.find("HexLimitArc") != def->tags.end();
			def->isHull = def->tags.find("HullSystem") != def->tags.end();
			def->isApplied = def->tags.find("Applied") != def->tags.end();
			def->exteriorCore = def->tags.find("ExteriorCore") != def->tags.end();
			def->defaultUnlock = def->tags.find("DefaultUnlock") != def->tags.end();
			def->passExterior = def->tags.find("PassExterior") != def->tags.end();
			def->fauxExterior = def->tags.find("FauxExterior") != def->tags.end();
		});

		subsysBlock("Hull", [&](std::string& value) {
			std::vector<std::string> tags;
			split(value, tags, ',', true);

			foreach(t, tags) {
				def->hullTags.push_back(*t);
				*t += "Hull";
			}
			addTags(tags);
		});

		subsysBlock("EvaluationOrder", [&](std::string& value) {
			def->ordering = toNumber<int>(value);
		});

		subsysBlock("DamageOrder", [&](std::string& value) {
			def->damageOrder = toNumber<int>(value);
		});

		subsysBlock("OnCheckErrors", [&](std::string& value) {
			def->def_onCheckErrors = value;
		});

		subsysBlock("State", [&](std::string& value) {
			std::vector<std::string> args;
			split(value, args, '=', true);

			if(args.size() != 2) {
				error(handler.position());
				error("  Invalid state format.");
				return;
			}

			SubsystemDef::StateDesc desc;

			toLowercase(args[0]);
			if(args[0] == "int")
				desc.type = BT_Int;
			else if(args[0] == "double")
				desc.type = BT_Double;
			else if(args[0] == "bool")
				desc.type = BT_Bool;

			desc.formula = 0;
			desc.str_formula = args[1];
			def->states.push_back(desc);
		});

		subsysBlock("Hook", [&](std::string& value) {
			def->hooks.push_back(value);
		});

		subsysBlock("AddShipModifier", [&](std::string& value) {
			SubsystemDef::ShipModifier mod;
			parseShipModifier(mod, value);

			def->shipModifiers.push_back(mod);
		});

		subsysBlock("AddAdjacentModifier", [&](std::string& value) {
			SubsystemDef::ShipModifier mod;
			parseShipModifier(mod, value);

			def->adjacentModifiers.push_back(mod);
		});

		subsysBlock("AddPostModifier", [&](std::string& value) {
			SubsystemDef::ShipModifier mod;
			parseShipModifier(mod, value);

			def->postModifiers.push_back(mod);
		});

		subsysBlock.defaultHandler([&](std::string& key, std::string& value) {
			if(!value.empty() && value[0] == '=') {
				SubsystemDef::Variable& var = getVariable(key);
				value = value.substr(1, value.size() - 1);
				var.formula = 0;
				var.str_formula = value;
			}
			else {
				error(handler.position());
				error("  Invalid line format.");
			}
		});

		{
			auto& defaultsBlock = subsysBlock.block("Defaults");
			defaultsBlock.defaultHandler([&](std::string& key, std::string& value) {
				if(!value.empty() && value[0] == '=') {
					SubsystemDef::Variable& var = getVariable(key);
					if(var.formula == 0 && var.str_formula.empty()) {
						value = value.substr(1, value.size() - 1);
						var.formula = 0;
						var.str_formula = value;
					}
				}
				else {
					error(handler.position());
					error("  Invalid line format.");
				}
			});
		}

		{
			auto& modifyBlock = subsysBlock.block("Modifier");
			modifyBlock.openBlock([&](std::string& value) -> bool {
				std::vector<std::string> args;
				std::string name;

				//Check if we have any arguments
				if(!funcSplit(value, name, args)) {
					name = value;
					args.clear();
				}

				//Check for duplicates
				auto it = def->modifierIds.find(name);
				if(it != def->modifierIds.end()) {
					//Ignored silently in templates so subsystems can
					//override modifiers from templates
					if(!inTemplate) {
						error(handler.position());
						error("  Duplicate modifier '%s'.", name.c_str());
					}
					stage = 0;
					return true;
				}

				//Make the stage
				stage = new SubsystemDef::ModifyStage();
				stage->umodifid = ModifiersByID.size();
				stage->index = def->modifiers.size();
				for(unsigned i = 0, cnt = args.size(); i < cnt; ++i)
					stage->argumentNames[args[i]] = i;
				def->modifiers.push_back(stage);
				def->modifierIds[name] = stage;
				stage->stage = ++modStage;
				ModifiersByID.push_back(stage);
				return true;
			});

			modifyBlock("Stage", [&](std::string& value) {
				if(!stage)
					return;
				stage->stage = toNumber<short>(value) << 16 | modStage;
			});

			modifyBlock.closeBlock([&]() {
				stage = 0;
			});

			modifyBlock.defaultHandler([&](std::string& key, std::string& value) {
				if(!stage)
					return;
				if(!value.empty() && value[0] == '=') {
					SubsystemDef::Variable& var = getVariable(key);

					value = value.substr(1, value.size() - 1);
					switch(var.type) {
						case SVT_SubsystemVariable: {
							auto it = stage->variables.find(var.index);
							if(it != stage->variables.end()) {
								error(handler.position());
								error("  Duplicate variable modifier.");
								return;
							}

							stage->str_variables.push_back(std::pair<int,std::string>(var.index, value));
						} break;
						case SVT_HexVariable: {
							auto it = stage->hexVariables.find(var.index);
							if(it != stage->hexVariables.end()) {
								error(handler.position());
								error("  Duplicate variable modifier.");
								return;
							}

							stage->str_hexVariables.push_back(std::pair<int,std::string>(var.index, value));
						} break;
						case SVT_ShipVariable: {
							auto it = stage->shipVariables.find(var.index);
							if(it != stage->shipVariables.end()) {
								error(handler.position());
								error("  Duplicate variable modifier.");
								return;
							}

							stage->str_shipVariables.push_back(std::pair<int,std::string>(var.index, value));
						} break;
					}
				}
				else {
					error(handler.position());
					error("  Invalid line format.");
				}
			});
		}

		{
			auto& moduleBlock = subsysBlock.block("Module");
			moduleBlock.openBlock([&](std::string& value) -> bool {
				auto it = def->moduleIndices.find(value);
				if(it != def->moduleIndices.end()) {
					if(inTemplate) {
						mod = def->modules[it->second];
						return true;
					}
					error(handler.position());
					error("  Duplicate module.");
					return false;
				}

				mod = new SubsystemDef::ModuleDesc();
				def->modules.push_back(mod);

				mod->index = def->modules.size() - 1;
				mod->id = value;

				mod->umodident = def->id + "::" + mod->id;
				mod->umodid = ModulesByID.size();
				ModulesByID.push_back(mod);

				if(value == "Default") {
					def->defaultModule = mod;
					mod->defaultUnlock = true;
				}
				else if(value == "Core") {
					def->coreModule = mod;
					mod->defaultUnlock = true;
					mod->required = true;
					mod->vital = true;
					mod->unique = true;
				}

				def->moduleIndices[value] = mod->index;
				return true;
			});

			moduleBlock.closeBlock([&]() {
				mod = 0;
				stage = 0;
			});

			moduleBlock("Name", [&](std::string& value) {
				mod->name = devices.locale.localize(value);
			});

			moduleBlock("Description", [&](std::string& value) {
				mod->description = devices.locale.localize(value);
			});

			moduleBlock("Color", [&](std::string& value) {
				mod->color = toColor(value);
			});

			moduleBlock("Required", [&](std::string& value) {
				mod->required = toBool(value);
			});

			moduleBlock("Unique", [&](std::string& value) {
				mod->unique = toBool(value);
			});

			moduleBlock("Vital", [&](std::string& value) {
				mod->vital = toBool(value);
			});

			moduleBlock("DefaultUnlock", [&](std::string& value) {
				mod->defaultUnlock = toBool(value);
			});

			moduleBlock("Sprite", [&](std::string& value) {
				mod->spriteMat = value;
			});

			moduleBlock("DrawMode", [&](std::string& value) {
				mod->drawMode = toNumber<int>(value);
			});

			moduleBlock("Hook", [&](std::string& value) {
				mod->hooks.push_back(value);
			});

			moduleBlock("OnEnable", [&](std::string& value) {
				mod->def_onEnable = value;
			});

			moduleBlock("OnDisable", [&](std::string& value) {
				mod->def_onDisable = value;
			});

			moduleBlock("AddModifier", [&](std::string& value) {
				mod->str_appliedStages.push_back(value);
			});

			moduleBlock("AddUniqueModifier", [&](std::string& value) {
				mod->str_uniqueAppliedStages.push_back(value);
			});

			moduleBlock("AddHexModifier", [&](std::string& value) {
				mod->str_hexAppliedStages.push_back(value);
			});

			moduleBlock("OnCheckErrors", [&](std::string& value) {
				mod->def_onCheckErrors = value;
			});

			moduleBlock("Tags", [&](std::string& value) {
				std::vector<std::string> tags;
				split(value, tags, ',', true);

				foreach(t, tags) {
					std::string tag, value;
					auto pos = t->find(':');
					if(pos != std::string::npos) {
						tag = t->substr(0, pos);
						if(pos < t->size()-1)
							value = t->substr(pos+1);
					}
					else {
						tag = *t;
					}

					mod->tags.insert(tag);

					auto it = numericTags.find(tag);
					int index = -1;
					if(it != numericTags.end()) {
						index = it->second;
					}
					else {
						index = numericTags.size();
						numericTags[tag] = index;
					}

					mod->numTags.insert(index);
					if(!value.empty())
						mod->tagValues[index].push_back(value);
				}
			});

			moduleBlock("AddAdjacentModifier", [&](std::string& value) {
				SubsystemDef::ShipModifier m;
				parseShipModifier(m, value);

				mod->adjacentModifiers.push_back(m);
			});

			auto addModification = [&](std::string& key, std::string& value) {
				SubsystemDef::Variable& var = getVariable(key);

				//Create a default stage at 0
				if(!stage) {
					mod->modifiers.push_back(SubsystemDef::ModifyStage());
					stage = &mod->modifiers.back();
					stage->stage = ++modStage;
				}

				switch(var.type) {
					case SVT_SubsystemVariable: {
						auto it = stage->variables.find(var.index);
						if(it != stage->variables.end()) {
							error(handler.position());
							error("  Duplicate variable modifier.");
							return;
						}

						stage->str_variables.push_back(std::pair<int,std::string>(var.index, value));
					} break;
					case SVT_HexVariable: {
						auto it = stage->hexVariables.find(var.index);
						if(it != stage->hexVariables.end()) {
							error(handler.position());
							error("  Duplicate variable modifier.");
							return;
						}

						stage->str_hexVariables.push_back(std::pair<int,std::string>(var.index, value));
					} break;
					case SVT_ShipVariable: {
						auto it = stage->shipVariables.find(var.index);
						if(it != stage->shipVariables.end()) {
							error(handler.position());
							error("  Duplicate variable modifier.");
							return;
						}

						stage->str_shipVariables.push_back(std::pair<int,std::string>(var.index, value));
					} break;
				}
			};

			moduleBlock.defaultHandler([&](std::string& key, std::string& value) {
				if(!value.empty() && value[0] == '=') {
					value = value.substr(1, value.size()-1);
					addModification(key, value);
				}
				else {
					error(handler.position());
					error("  Invalid line format.");
				}
			});

			{
				auto& assertBlock = moduleBlock.block("Assert");
				assertBlock.openBlock([&](std::string& value) -> bool {
					mod->asserts.push_back(SubsystemDef::Assert());
					ass = &mod->asserts.back();
					ass->fatal = true;
					ass->unique = false;
					ass->formula = 0;
					ass->str_formula = value;
					ass->message = "Assertion Failed";
					return true;
				});

				assertBlock("Unique", [&](std::string& value) {
					ass->unique = toBool(value);
				});

				assertBlock("Fatal", [&](std::string& value) {
					ass->fatal = toBool(value);
				});

				assertBlock("Message", [&](std::string& value) {
					ass->message = devices.locale.localize(value);
				});

				assertBlock.closeBlock([&]() {
					ass = 0;
				});
			}
			{
				auto& requiresBlock = moduleBlock.block("Requires");
				requiresBlock.openBlock([&](std::string& value) -> bool {
					return true;
				});

				requiresBlock.lineHandler([&](std::string& line) {
					auto pos = line.find("=");
					if(pos == line.npos) {
						error(handler.position());
						error("  Invalid line format.");
						return;
					}

					std::vector<std::string> args;
					split(line, args, '=', true);

					if(args.size() != 2) {
						error(handler.position());
						error("  Invalid line format.");
						return;
					}

					//Add the variable modification
					std::string vname = "Ship.REQUIRES_" + args[0];
					std::string vformula = format("Ship.REQUIRES_$1 + $2", args[0], args[1]);
					addModification(vname, vformula);

					//Add the assert block
					SubsystemDef::Assert ass;
					ass.fatal = true;
					ass.unique = true;
					ass.formula = 0;
					ass.str_formula = format("Ship.$1 >= Ship.REQUIRES_$1", args[0]);
					ass.message = devices.locale.localize(format("ERROR_INSUFFICIENT_$1", args[0]));

					mod->asserts.push_back(ass);
				});
			}
			{
				auto& providesBlock = moduleBlock.block("Provides");
				providesBlock.openBlock([&](std::string& value) -> bool {
					return true;
				});

				providesBlock.lineHandler([&](std::string& line) {
					auto pos = line.find("=");
					if(pos == line.npos) {
						error(handler.position());
						error("  Invalid line format.");
						return;
					}

					std::vector<std::string> args;
					split(line, args, '=', true);

					if(args.size() != 2) {
						error(handler.position());
						error("  Invalid line format.");
						return;
					}

					//Add the variable modification
					std::string vname = "Ship." + args[0];
					std::string vformula = format("Ship.$1 + $2", args[0], args[1]);
					addModification(vname, vformula);
				});
			}

			{
				auto& modifyBlock = moduleBlock.block("Modify");
				modifyBlock.openBlock([&](std::string& value) -> bool {
					short number = 0;
					bool unique = false;

					if(streq_nocase(value, "unique")) {
						unique = true;
					}
					else {
						if(streq_nocase(value, "unique ", 0, 7)) {
							unique = true;
							value = value.substr(7, value.size() - 7);
						}
						if(streq_nocase(value, "stage ", 0, 6)) {
							number = toNumber<short>(value.substr(6, value.size() - 6));
						}
						else if(!value.empty()) {
							error(handler.position());
							error("  Invalid stage specification, assuming stage 0.");
						}
					}

					if(unique) {
						mod->uniqueModifiers.push_back(SubsystemDef::ModifyStage());
						stage = &mod->uniqueModifiers.back();
					}
					else {
						mod->modifiers.push_back(SubsystemDef::ModifyStage());
						stage = &mod->modifiers.back();
					}

					stage->stage = number << 16 | ++modStage;
					return true;
				});

				modifyBlock.closeBlock([&]() {
					stage = 0;
				});

				modifyBlock.defaultHandler([&](std::string& key, std::string& value) {
					if(!value.empty() && value[0] == '=') {
						SubsystemDef::Variable& var = getVariable(key);

						value = value.substr(1, value.size() - 1);
						switch(var.type) {
							case SVT_SubsystemVariable: {
								auto it = stage->variables.find(var.index);
								if(it != stage->variables.end()) {
									error(handler.position());
									error("  Duplicate variable modifier.");
									return;
								}

								stage->str_variables.push_back(std::pair<int,std::string>(var.index, value));
							} break;
							case SVT_HexVariable: {
								auto it = stage->hexVariables.find(var.index);
								if(it != stage->hexVariables.end()) {
									error(handler.position());
									error("  Duplicate variable modifier.");
									return;
								}

								stage->str_hexVariables.push_back(std::pair<int,std::string>(var.index, value));
							} break;
							case SVT_ShipVariable: {
								auto it = stage->shipVariables.find(var.index);
								if(it != stage->shipVariables.end()) {
									error(handler.position());
									error("  Duplicate variable modifier.");
									return;
								}

								stage->str_shipVariables.push_back(std::pair<int,std::string>(var.index, value));
							} break;
						}
					}
					else {
						error(handler.position());
						error("  Invalid line format.");
					}
				});
			}

			{
				auto& effectBlock = moduleBlock.block("Effect");
				effectBlock.openBlock([&](std::string& value) -> bool {
					const EffectDef* type = getEffectDefinition(value);
					if(!type) {
						eff = 0;
						error(handler.position());
						error("  Unknown effect %s.", value.c_str());
						return false;
					}
					mod->effects.push_back(SubsystemDef::Effect());
					eff = &mod->effects[mod->effects.size() - 1];
					eff->type = type;
					eff->values.resize(type->valueCount);
					eff->str_values.resize(type->valueCount);

					for(unsigned i = 0; i < type->valueCount; ++i)
						eff->values[i] = 0;
					return true;
				});

				effectBlock.closeBlock([&]() {
					eff = 0;
				});

				effectBlock.lineHandler([&](std::string& line) {
					auto pos = line.find("=");
					if(pos == line.npos) {
						error(handler.position());
						error("  Invalid line format.");
						return;
					}

					std::vector<std::string> args;
					split(line, args, '=', true);

					if(args.size() != 2) {
						error(handler.position());
						error("  Invalid line format.");
						return;
					}

					auto it = eff->type->valueNames.find(args[0]);
					if(it == eff->type->valueNames.end()) {
						error(handler.position());
						error("  Unknown effect value '%s'.", args[0].c_str());
						return;
					}

					eff->str_values[it->second] = args[1];
				});
			}
		}

		{
			auto& effectBlock = subsysBlock.block("Effect");
			effectBlock.openBlock([&](std::string& value) -> bool {
				const EffectDef* type = getEffectDefinition(value);
				if(!type) {
					eff = 0;
					error(handler.position());
					error("  Unknown effect %s.", value.c_str());
					return false;
				}
				def->effects.push_back(SubsystemDef::Effect());
				eff = &def->effects[def->effects.size() - 1];
				eff->type = type;
				eff->values.resize(type->valueCount);
				eff->str_values.resize(type->valueCount);

				for(unsigned i = 0; i < type->valueCount; ++i)
					eff->values[i] = 0;
				return true;
			});

			effectBlock.closeBlock([&]() {
				eff = 0;
			});

			effectBlock.lineHandler([&](std::string& line) {
				auto pos = line.find("=");
				if(pos == line.npos) {
					error(handler.position());
					error("  Invalid line format.");
					return;
				}

				std::vector<std::string> args;
				split(line, args, '=', true);

				if(args.size() != 2) {
					error(handler.position());
					error("  Invalid line format.");
					return;
				}

				auto it = eff->type->valueNames.find(args[0]);
				if(it == eff->type->valueNames.end()) {
					error(handler.position());
					error("  Unknown effect value '%s'.", args[0].c_str());
					return;
				}

				eff->str_values[it->second] = args[1];
			});
		}
		{
			auto& effectorBlock = subsysBlock.block("Effector");
			effectorBlock.openBlock([&](std::string& value) -> bool {
				const EffectorDef* type = getEffectorDefinition(value);
				if(!type) {
					efftr = 0;
					error(handler.position());
					error("  Unknown effector %s.", value.c_str());
					return false;
				}
				def->effectors.push_back(SubsystemDef::Effector());
				efftr = &def->effectors[def->effectors.size() - 1];
				efftr->type = type;
				efftr->enabled = true;
				efftr->values.resize(type->valueCount);
				efftr->str_values.resize(type->valueCount);
				efftr->skinIndex = 0;

				for(unsigned i = 0; i < type->valueCount; ++i)
					efftr->values[i] = 0;
				return true;
			});

			effectorBlock("Disabled", [&](std::string& value) {
				efftr->enabled = !toBool(value);
			});

			effectorBlock("Skin", [&](std::string& value) {
				auto s = efftr->type->skinNames.find(value);
				if(s != efftr->type->skinNames.end()) {
					efftr->skinIndex = s->second;
					efftr->skinName = value;
				}
				else
					error("Effector '%s' has no skin '%s'", efftr->type->name.c_str(), value.c_str());
			});

			effectorBlock.closeBlock([&]() {
				efftr = 0;
			});

			effectorBlock.lineHandler([&](std::string& line) {
				auto pos = line.find("=");
				if(pos == line.npos) {
					error(handler.position());
					error("  Invalid line format.");
					return;
				}

				std::vector<std::string> args;
				split(line, args, '=', true);

				if(args.size() != 2) {
					error(handler.position());
					error("  Invalid line format.");
					return;
				}

				auto it = efftr->type->valueNames.find(args[0]);
				if(it == efftr->type->valueNames.end()) {
					error(handler.position());
					error("  Unknown effector value '%s'.\n", args[0].c_str());
					return;
				}

				efftr->str_values[it->second] = args[1];
			});
		}
		{
			auto& assertBlock = subsysBlock.block("Assert");
			assertBlock.openBlock([&](std::string& value) -> bool {
				def->asserts.push_back(SubsystemDef::Assert());
				ass = &def->asserts.back();
				ass->fatal = true;
				ass->unique = false;
				ass->formula = 0;
				ass->str_formula = value;
				ass->message = "Assertion Failed";
				return true;
			});

			assertBlock("Unique", [&](std::string& value) {
				ass->unique = toBool(value);
			});

			assertBlock("Fatal", [&](std::string& value) {
				ass->fatal = toBool(value);
			});

			assertBlock("Message", [&](std::string& value) {
				ass->message = devices.locale.localize(value);
			});

			assertBlock.closeBlock([&]() {
				ass = 0;
			});
		}
		{
			auto& requiresBlock = subsysBlock.block("Requires");
			requiresBlock.openBlock([&](std::string& value) -> bool {
				return true;
			});

			requiresBlock.lineHandler([&](std::string& line) {
				auto pos = line.find("=");
				if(pos == line.npos) {
					error(handler.position());
					error("  Invalid line format.");
					return;
				}

				std::vector<std::string> args;
				split(line, args, '=', true);

				if(args.size() != 2) {
					error(handler.position());
					error("  Invalid line format.");
					return;
				}

				//Add the variable modification
				std::string vname = "Ship.REQUIRES_" + args[0];
				auto& var = getVariable(vname);
				var.str_formula = format("Ship.REQUIRES_$1 + $2",
					args[0], args[1]);

				//Add the assert block
				SubsystemDef::Assert ass;
				ass.fatal = true;
				ass.unique = true;
				ass.formula = 0;
				ass.str_formula = format("Ship.$1 >= Ship.REQUIRES_$1", args[0]);
				ass.message = devices.locale.localize(format("ERROR_INSUFFICIENT_$1", args[0]));

				def->asserts.push_back(ass);
			});
		}
		{
			auto& providesBlock = subsysBlock.block("Provides");
			providesBlock.openBlock([&](std::string& value) -> bool {
				return true;
			});

			providesBlock.lineHandler([&](std::string& line) {
				auto pos = line.find("=");
				if(pos == line.npos) {
					error(handler.position());
					error("  Invalid line format.");
					return;
				}

				std::vector<std::string> args;
				split(line, args, '=', true);

				if(args.size() != 2) {
					error(handler.position());
					error("  Invalid line format.");
					return;
				}

				//Add the variable modification
				std::string vname = "Ship." + args[0];
				auto& var = getVariable(vname);
				var.str_formula = format("Ship.$1 + $2", args[0], args[1]);
			});
		}
	}

	handler.read(filename);

	SV_Size = getVariableIndex("Size");
	HV_Resistance = getHexVariableIndex("Resistance");
	HV_HP = getHexVariableIndex("HP");
	ShV_HexSize = getShipVariableIndex("HexSize");
}

void bindSubsystemHooks() {
	foreach(it, subsystems) {
		SubsystemDef* def = (*it);

		if(!def->def_onCheckErrors.empty())
			def->scr_onCheckErrors = devices.scripts.server->getFunction(def->def_onCheckErrors,
				"(Design& design, Subsystem& sys)", "bool");

		foreach(it, def->modules) {
			auto* m = *it;
			if(!m->def_onCheckErrors.empty())
				m->scr_onCheckErrors = devices.scripts.server->getFunction(m->def_onCheckErrors,
					"(Design& design, Subsystem& sys, const vec2u& hex)", "bool");
		}

		if(!devices.network->isClient) {
			foreach(it, def->modules) {
				auto* m = *it;
				if(!m->def_onEnable.empty()) {
					m->scr_onEnable = devices.scripts.server->getFunction(m->def_onEnable,
						"(Event& evt, const vec2u& position)", "void");
				}
				else {
					m->scr_onEnable = 0;
				}

				if(!m->def_onDisable.empty()) {
					m->scr_onDisable = devices.scripts.server->getFunction(m->def_onDisable,
						"(Event& evt, const vec2u& position)", "void");
				}
				else {
					m->scr_onDisable = 0;
				}
			}
		}
	}
}

void executeSubsystemTemplates() {
	foreach(it, subsystems) {
		SubsystemDef* cur = (*it);

		//Add templated code
		foreach(t, templates) {
			if(conditionMatches(cur, (*t)->conditions)) {
				modStage = 1;
				def = cur;
				mod = 0;
				stage = 0;
				eff = 0;
				efftr = 0;
				ass = 0;
				temp = 0;
				inTemplate = true;

				sysHandler->enterBlock("Subsystem");
				foreach(l, (*t)->lines)
					sysHandler->feed(*l);
				sysHandler->end();
			}
		}
	}
}

void finalizeSubsystems() {
	foreach(it, subsystems)
		(*it)->finalize();
}

void bindSubsystemMaterials() {
	foreach(it, subsystems) {
		SubsystemDef* def = (*it);

		foreach(m, def->modules)
			(*m)->sprite = devices.library.getSprite((*m)->spriteMat);

		if(!def->picMat.empty())
			def->picture = devices.library.getSprite(def->picMat);
		else if(def->coreModule)
			def->picture = def->coreModule->sprite;
		else if(def->defaultModule)
			def->picture = def->defaultModule->sprite;
	}
}

SubsystemDef::SubsystemDef() : index(-1), ordering(0), damageOrder(0), elevation(0),
	defaultModule(0), coreModule(0), typeColor((unsigned)0x00000000),
	scr_onCheckErrors(0),
	hasCore(false), isContiguous(true), exteriorCore(false),
	defaultUnlock(false), isHull(false), isApplied(false), hexLimitArc(false),
	passExterior(false), fauxExterior(false) {
}

SubsystemDef::~SubsystemDef() {
	foreach(it, variables) {
		delete it->formula;
	}

	foreach(it, effects) {
		foreach(f, it->values)
			delete *f;
	}

	foreach(it, states)
		delete it->formula;
}

void SubsystemDef::finalize() {
	//Create default module
	if(!defaultModule) {
		SubsystemDef::ModuleDesc* mod = new SubsystemDef::ModuleDesc();
		modules.push_back(mod);

		mod->index = modules.size() - 1;
		mod->id = "Default";
		mod->umodident = id + "::" + mod->id;
		mod->umodid = ModulesByID.size();
		mod->defaultUnlock = true;
		ModulesByID.push_back(mod);
		defaultModule = mod;
		moduleIndices["Default"] = mod->index;
	}

	//Create core module
	if(hasCore && !coreModule) {
		SubsystemDef::ModuleDesc* mod = new SubsystemDef::ModuleDesc();
		modules.push_back(mod);

		mod->index = modules.size() - 1;
		mod->id = "Core";
		mod->umodident = id + "::" + mod->id;
		mod->umodid = ModulesByID.size();
		mod->defaultUnlock = true;
		ModulesByID.push_back(mod);
		coreModule = mod;
		moduleIndices["Core"] = mod->index;
	}

	auto loadFormula = [this](const std::string& str) -> Formula* {
		try {
			formulaQuiet = false;
			return Formula::fromInfix(str.c_str(), formulaVarIndex, false);
		}
		catch(FormulaError err) {
			error("Error in Subsystem '%s' formula '%s': %s", id.c_str(), str.c_str(), err.msg.c_str());
			return Formula::fromInfix("0");
		}
	};

	auto loadFormula_quiet = [this](const std::string& str) -> Formula* {
		try {
			formulaQuiet = true;
			return Formula::fromInfix(str.c_str(), formulaVarIndex, false);
		}
		catch(FormulaError err) {
			return nullptr;
		}
	};

	auto addModifier = [this](const std::string& name, const std::string& argname, int prior) -> ModifyStage* {
		//Check for duplicates
		auto it = modifierIds.find(name);
		if(it != modifierIds.end())
			return nullptr;

		//Make the stage
		auto* stage = new ModifyStage();
		stage->index = modifiers.size();
		stage->umodifid = ModifiersByID.size();
		stage->argumentNames[argname] = 0;
		stage->stage = prior;
		ModifiersByID.push_back(stage);
		modifiers.push_back(stage);
		modifierIds[name] = stage;
		return stage;
	};

	auto addVariableModifiers = [this,addModifier](SubsystemDef::Variable& var) {
		auto* stage = addModifier(var.name+"Factor", "factor", 30);
		if(stage) {
			switch(var.type) {
				case SVT_SubsystemVariable:
					stage->str_variables.push_back(std::pair<int,std::string>(var.index, var.name+" * factor"));
				break;
				case SVT_HexVariable:
					stage->str_hexVariables.push_back(std::pair<int,std::string>(var.index, "Hex."+var.name+" * factor"));
				break;
			}
		}

		stage = addModifier("AddBase"+var.name+"Factor", "factor", -20);
		if(stage) {
			switch(var.type) {
				case SVT_SubsystemVariable:
					stage->str_variables.push_back(std::pair<int,std::string>(var.index, var.name+" + Base::"+var.name+" * factor"));
				break;
				case SVT_HexVariable:
					stage->str_hexVariables.push_back(std::pair<int,std::string>(var.index, "Hex."+var.name+" + Base::Hex."+var.name+" * factor"));
				break;
			}
		}

		stage = addModifier("Add"+var.name, "amount", -10);
		if(stage) {
			switch(var.type) {
				case SVT_SubsystemVariable:
					stage->str_variables.push_back(std::pair<int,std::string>(var.index, var.name+" + amount"));
				break;
				case SVT_HexVariable:
					stage->str_hexVariables.push_back(std::pair<int,std::string>(var.index, "Hex."+var.name+" + amount"));
				break;
			}
		}
	};

	//Parse all formulas
	formulaSubsystem = this;
	foreach(it, variables) {
		it->formula = loadFormula(it->str_formula);
		addVariableModifiers(*it);
	}
	foreach(it, hexVariables) {
		it->formula = loadFormula(it->str_formula);
		addVariableModifiers(*it);
	}
	foreach(it, shipVariables)
		it->formula = loadFormula(it->str_formula);
	foreach(it, states)
		it->formula = loadFormula(it->str_formula);
	foreach(it, asserts)
		it->formula = loadFormula(it->str_formula);
	foreach(it, shipModifiers)
		for(unsigned i = 0, cnt = it->str_arguments.size(); i < cnt; ++i)
			it->stage.formulas[i] = loadFormula(it->str_arguments[i]);
	foreach(it, postModifiers)
		for(unsigned i = 0, cnt = it->str_arguments.size(); i < cnt; ++i)
			it->stage.formulas[i] = loadFormula(it->str_arguments[i]);
	foreach(it, adjacentModifiers)
		for(unsigned i = 0, cnt = it->str_arguments.size(); i < cnt; ++i)
			it->stage.formulas[i] = loadFormula(it->str_arguments[i]);
	foreach(it, hooks)
		for(unsigned i = 0, cnt = it->str_args.size(); i < cnt; ++i)
			it->formulas[i] = loadFormula_quiet(it->str_args[i]);
	foreach(it, effects)
		for(unsigned i = 0, cnt = it->str_values.size(); i < cnt; ++i)
			it->values[i] = loadFormula(it->str_values[i]);
	foreach(it, effectors)
		for(unsigned i = 0, cnt = it->str_values.size(); i < cnt; ++i)
			it->values[i] = loadFormula(it->str_values[i]);
	foreach(it, modules) {
		foreach(m, (*it)->modifiers) {
			foreach(v, m->str_variables)
				m->variables[v->first] = loadFormula(v->second);
			foreach(v, m->str_hexVariables)
				m->hexVariables[v->first] = loadFormula(v->second);
			foreach(v, m->str_shipVariables)
				m->shipVariables[v->first] = loadFormula(v->second);
		}
		foreach(ass, (*it)->asserts)
			ass->formula = loadFormula(ass->str_formula);
		foreach(h, (*it)->hooks)
			for(unsigned i = 0, cnt = h->str_args.size(); i < cnt; ++i)
				h->formulas[i] = loadFormula_quiet(h->str_args[i]);
	}
	foreach(m, modifiers) {
		formulaModifier = *m;
		foreach(v, (*m)->str_variables)
			(*m)->variables[v->first] = loadFormula(v->second);
		foreach(v, (*m)->str_hexVariables)
			(*m)->hexVariables[v->first] = loadFormula(v->second);
		foreach(v, (*m)->str_shipVariables)
			(*m)->shipVariables[v->first] = loadFormula(v->second);
	}
	formulaModifier = 0;

	//Check that we have values for all effect variables
	for(auto i = effects.begin(), end = effects.end(); i != end; ++i) {
		for(unsigned n = 0; n < i->type->valueCount; ++n) {
			auto& desc = i->type->values[n];
			if(i->values[n] == 0 && !desc.defaultValue) {
				error("Error: Subsystem '%s' effect '%s' is missing values", id.c_str(), i->type->name.c_str());
				break;
			}
		}
	}

	//Check that we have values for all effector variables
	for(auto i = effectors.begin(), end = effectors.end(); i != end; ++i) {
		for(unsigned n = 0; n < i->type->valueCount; ++n) {
			auto& desc = i->type->values[n];
			if(i->values[n] == 0 && !desc.defaultValue) {
				error("Error: Subsystem '%s' effector '%s' is missing values", id.c_str(), i->type->name.c_str());
				break;
			}
		}
	}

	//Parse module applied stages
	auto makeAppliedStage = [&](std::string& line, std::vector<SubsystemDef::AppliedStage>& list) {
		std::string name;
		std::vector<std::string> args;
		bool isOptional = false;

		if(line.compare(0, 9, "optional ") == 0) {
			line = line.substr(9);
			isOptional = true;
		}

		if(!funcSplit(line, name, args)) {
			name = line;
			args.clear();
		}

		auto it = modifierIds.find(name);
		if(it == modifierIds.end()) {
			if(!isOptional) {
				error("Error: could not add modifier '%s.%s'.",
					id.c_str(), name.c_str());
			}
			return;
		}

		const SubsystemDef::ModifyStage* stage = it->second;

		if(stage->argumentNames.size() != args.size()) {
			error("Error: Modifier '%s.%s' requires %d argument(s), %d given.",
				id.c_str(), name.c_str(),
				stage->argumentNames.size(), args.size());
			return;
		}

		list.push_back(SubsystemDef::AppliedStage());
		SubsystemDef::AppliedStage& as = list.back();

		as.stage = stage;
		for(unsigned i = 0, cnt = args.size(); i < cnt; ++i)
			as.formulas[i] = Formula::fromInfix(args[i].c_str(), formulaVarIndex);
	};

	foreach(m, modules) {
		foreach(it, (*m)->str_appliedStages)
			makeAppliedStage(*it, (*m)->appliedStages);
		foreach(it, (*m)->str_uniqueAppliedStages)
			makeAppliedStage(*it, (*m)->uniqueAppliedStages);
		foreach(it, (*m)->str_hexAppliedStages)
			makeAppliedStage(*it, (*m)->hexAppliedStages);
		foreach(it, (*m)->adjacentModifiers)
			for(unsigned i = 0, cnt = it->str_arguments.size(); i < cnt; ++i)
				it->stage.formulas[i] = loadFormula(it->str_arguments[i]);
		foreach(it, (*m)->effects)
			for(unsigned i = 0, cnt = it->str_values.size(); i < cnt; ++i)
				it->values[i] = loadFormula(it->str_values[i]);

		//Check that we have values for all effect variables
		for(auto i = (*m)->effects.begin(), end = (*m)->effects.end(); i != end; ++i) {
			for(unsigned n = 0; n < i->type->valueCount; ++n) {
				auto& desc = i->type->values[n];
				if(i->values[n] == 0 && !desc.defaultValue) {
					error("Error: Subsystem '%s', module '%s', effect '%s' is missing values", id.c_str(),
							(*m)->name.c_str(), i->type->name.c_str());
					break;
				}
			}
		}
	}
	formulaSubsystem = 0;
}

bool SubsystemDef::hasHullTag(const std::string& tag) const {
	foreach(it, hullTags)
		if(tag == *it)
			return true;
	return false;
}

bool SubsystemDef::canUseOn(const HullDef* hull) const {
	if(!hull)
		return false;
	foreach(it, hullTags)
		if(hull->hasTag(*it))
			return true;
	return false;
}

bool SubsystemDef::onCheckErrors(Design* design, Subsystem* sys) const {
	if(!scr_onCheckErrors)
		return false;

	scripts::Call cl = devices.scripts.server->call(scr_onCheckErrors);
	bool ret = false;
	if(cl.valid()) {
		cl.push(design);
		cl.push(sys);
		cl.call(ret);
	}
	return ret;
}

bool SubsystemDef::ModuleDesc::onCheckErrors(Design* design, Subsystem* sys, const vec2u& hex) const {
	if(!scr_onCheckErrors)
		return false;

	scripts::Call cl = devices.scripts.server->call(scr_onCheckErrors);
	bool ret = false;
	if(cl.valid()) {
		cl.push(design);
		cl.push(sys);
		cl.push(&hex);
		cl.call(ret);
	}
	return ret;
}

void SubsystemDef::ModuleDesc::onEnable(EffectEvent& evt, const vec2u& position) const {
	if(!scr_onEnable)
		return;

	scripts::Call cl = devices.scripts.server->call(scr_onEnable);
	if(cl.valid()) {
		cl.push(&evt);
		cl.push(&position);
		cl.call();
	}
}

void SubsystemDef::ModuleDesc::onDisable(EffectEvent& evt, const vec2u& position) const {
	if(!scr_onDisable)
		return;

	scripts::Call cl = devices.scripts.server->call(scr_onDisable);
	if(cl.valid()) {
		cl.push(&evt);
		cl.push(&position);
		cl.call();
	}
}

bool SubsystemDef::hasTag(const std::string& tag) const {
	auto it = tags.find(tag);
	return it != tags.end();
}

bool SubsystemDef::hasTag(int index) const {
	auto it = numTags.find(index);
	return it != numTags.end();
}

static std::string ERR = "ERR";
const std::string& SubsystemDef::getTagValue(int index, unsigned num) const {
	auto it = tagValues.find(index);
	if(it != tagValues.end()) {
		if(num >= it->second.size())
			return ERR;
		return it->second[num];
	}
	return ERR;
}

unsigned SubsystemDef::getTagValueCount(int index) const {
	auto it = tagValues.find(index);
	if(it != tagValues.end())
		return it->second.size();
	return 0;
}

bool SubsystemDef::hasTagValue(int index, const std::string& value) const {
	auto it = tagValues.find(index);
	if(it != tagValues.end()) {
		for(size_t i = 0, cnt = it->second.size(); i < cnt; ++i) {
			if(it->second[i] == value)
				return true;
		}
	}
	return false;
}

bool SubsystemDef::ModuleDesc::hasTag(const std::string& tag) const {
	auto it = tags.find(tag);
	return it != tags.end();
}

bool SubsystemDef::ModuleDesc::hasTag(int index) const {
	auto it = numTags.find(index);
	return it != numTags.end();
}

const std::string& SubsystemDef::ModuleDesc::getTagValue(int index, unsigned num) const {
	auto it = tagValues.find(index);
	if(it != tagValues.end()) {
		if(num >= it->second.size())
			return ERR;
		return it->second[num];
	}
	return ERR;
}

unsigned SubsystemDef::ModuleDesc::getTagValueCount(int index) const {
	auto it = tagValues.find(index);
	if(it != tagValues.end())
		return it->second.size();
	return 0;
}

bool SubsystemDef::ModuleDesc::hasTagValue(int index, const std::string& value) const {
	auto it = tagValues.find(index);
	if(it != tagValues.end()) {
		for(size_t i = 0, cnt = it->second.size(); i < cnt; ++i) {
			if(it->second[i] == value)
				return true;
		}
	}
	return false;
}

struct LookupData {
	Design* design;
	Subsystem* system;
	int hexIndex;
	float args[MODIFY_STAGE_MAXARGS];
};

Threaded(LookupData) lookupData;

static double formulaVariable(void* user, const std::string* name) {
	return 0.0;
}

static double formulaIndex(void* user, int index) {
	if(index == -1)
		return 0.0;

	bool isBase = (index & VTF_BaseVariable) != 0;
	VariableType type = (VariableType)(index & 0x7f000000);
	index &= 0x00ffffff;

	switch(type) {
		case VT_ConstantVariable:
			switch(index) {
				case CV_Hexes:
					return lookupData.system->hexes.size();
				case CV_InteriorHexes:
					return lookupData.system->hexes.size() - lookupData.system->exteriorHexes;
				case CV_ExteriorHexes:
					return lookupData.system->exteriorHexes;
				case CV_HexSize:
					return lookupData.design->hexSize;
				case CV_ShipSize:
					return lookupData.design->size;
				case CV_ShipTotalHexes:
					return lookupData.design->hull->activeCount;
				case CV_ShipUsedHexes:
					return lookupData.design->usedHexCount;
				case CV_ShipEmptyHexes:
					return lookupData.design->hull->activeCount - lookupData.design->usedHexCount;
				case CV_IsCore:
					if(lookupData.hexIndex < 0 || (unsigned)lookupData.hexIndex >= lookupData.system->hexes.size())
						return 0.0;
					return (lookupData.system->modules[lookupData.hexIndex] == lookupData.system->type->coreModule) ? 1.0 : 0.0;
				case CV_HexExterior:
					if(lookupData.hexIndex < 0)
						return 0.0;
					return lookupData.design->hull->isExterior(lookupData.system->hexes[lookupData.hexIndex]) ? 1.0 : 0.0;
				case CV_AdjacentActive: {
					if(lookupData.hexIndex < 0 || (unsigned)lookupData.hexIndex >= lookupData.system->hexes.size())
						return 0.0;
					const Design * design = lookupData.design;
					vec2u hex = lookupData.system->hexes[lookupData.hexIndex];
					double count = 0;
					for(unsigned d = 0; d < 6; ++d) {
						vec2u pos = hex;
						if(!design->hull->active.advance(pos.x, pos.y, HexGridAdjacency(d)))
							continue;
						if(!design->hull->active.get(pos))
							continue;
						count += 1.0;
					}
					return count;
				}
				case CV_AdjacentThis: {
					if(lookupData.hexIndex < 0 || (unsigned)lookupData.hexIndex >= lookupData.system->hexes.size())
						return 0.0;
					const Design * design = lookupData.design;
					vec2u hex = lookupData.system->hexes[lookupData.hexIndex];
					double count = 0;
					for(unsigned d = 0; d < 6; ++d) {
						vec2u pos = hex;
						if(!design->hull->active.advance(pos.x, pos.y, HexGridAdjacency(d)))
							continue;
						if(!design->hull->active.get(pos))
							continue;
						int sysId = design->grid.get(pos);
						if((unsigned)sysId >= design->subsystems.size())
							continue;
						if(&design->subsystems[sysId] != lookupData.system)
							continue;
						count += 1.0;
					}
					return count;
				}
			}
			return 0.0;
		case VT_GameConfig:
			if((size_t)index < gameConfig.count)
				return gameConfig.values[index];
			return 0.0;
		case VT_ModuleCount:
			if(index < 0 || index >= (int)lookupData.system->moduleCounts.size())
				return 0.0;
			return lookupData.system->moduleCounts[index];
		case VT_ModuleExists:
			if(index < 0 || index >= (int)lookupData.system->moduleCounts.size())
				return 0.0;
			return lookupData.system->moduleCounts[index] > 0 ? 1.0 : 0.0;
		case VT_HexVariable:
			//Make sure we're in a hex context
			if(lookupData.hexIndex < 0)
				return 0.0;

			//Lookup local index
			if(index < (int)lookupData.system->type->hexVariableIndices.size())
				index = lookupData.system->type->hexVariableIndices[index];
			else
				index = -1;

			//Lookup variable
			if(index < 0) {
				return 0.0;
			}
			else {
				unsigned baseIndex = lookupData.hexIndex * lookupData.system->type->hexVariables.size();
				if(isBase)
					return lookupData.system->hexBaseVariables[baseIndex + index];
				else
					return lookupData.system->hexVariables[baseIndex + index];
			}
		case VT_ShipVariable:
			//Lookup variable
			if(index < 0) {
				return 0.0;
			}
			else {
				return lookupData.design->shipVariables[index];
			}
		case VT_SubsystemVariable:
			//Lookup local index
			if(index < (int)lookupData.system->type->variableIndices.size())
				index = lookupData.system->type->variableIndices[index];
			else
				index = -1;

			//Lookup variable
			if(index < 0)
				return 0.0;
			else if(isBase)
				return lookupData.system->baseVariables[index];
			else
				return lookupData.system->variables[index];
		case VT_SumVariable: {
			if(lookupData.design == nullptr)
				return 0.0;
			double value = 0.0;
			for(size_t i = 0, cnt = lookupData.design->subsystems.size(); i < cnt; ++i) {
				auto* sys = &lookupData.design->subsystems[i];
				if(sys->variables == nullptr || sys->type == nullptr)
					continue;

				//Lookup local index
				int localIndex = -1;
				if((unsigned)index < (unsigned)sys->type->variableIndices.size())
					localIndex = sys->type->variableIndices[index];

				if(localIndex >= 0) {
					if(isBase)
						value += sys->baseVariables[localIndex];
					else
						value += sys->variables[localIndex];
				}
			}
			return value;
		}
		case VT_HexSumVariable: {
			if(lookupData.design == nullptr)
				return 0.0;
			double value = 0.0;
			for(size_t i = 0, cnt = lookupData.design->subsystems.size(); i < cnt; ++i) {
				auto* sys = &lookupData.design->subsystems[i];
				if(sys->hexVariables == nullptr || sys->type == nullptr)
					continue;

				//Lookup local index
				int localIndex = -1;
				if((unsigned)index < (unsigned)sys->type->hexVariableIndices.size())
					localIndex = sys->type->hexVariableIndices[index];
				if(localIndex < 0)
					continue;

				for(size_t h = 0, hexCnt = sys->hexes.size(); h < hexCnt; ++h) {
					if(sys == lookupData.system && h >= (unsigned)lookupData.hexIndex)
						break;
					int ind = h * sys->type->hexVariables.size() + localIndex;
					if(isBase)
						value += sys->hexBaseVariables[ind];
					else
						value += sys->hexVariables[ind];
				}
			}
			return value;
		}
		case VT_TagCountVariable: {
			if(lookupData.design == nullptr)
				return 0.0;
			double value = 0.0;
			for(size_t i = 0, cnt = lookupData.design->subsystems.size(); i < cnt; ++i) {
				if(lookupData.design->subsystems[i].type->hasTag(index))
					value += 1.0;
			}
			return value;
		}
		case VT_Argument:
			if(index >= 0 && index < MODIFY_STAGE_MAXARGS)
				return lookupData.args[index];
			else
				return 0.0;
		case VT_AdjacentTag: {
			if(lookupData.hexIndex < 0 || (unsigned)lookupData.hexIndex >= lookupData.system->hexes.size())
				return 0.0;
			const Design * design = lookupData.design;
			vec2u hex = lookupData.system->hexes[lookupData.hexIndex];
			double count = 0;
			for(unsigned d = 0; d < 6; ++d) {
				vec2u pos = hex;
				if(!design->hull->active.advance(pos.x, pos.y, HexGridAdjacency(d)))
					continue;
				if(!design->hull->active.get(pos))
					continue;
				int sysId = design->grid.get(pos);
				if((unsigned)sysId >= design->subsystems.size())
					continue;
				if(!design->subsystems[sysId].type->hasTag(index))
					continue;
				count += 1.0;
			}
			return count;
		}
		case VT_AdjacentSubsystem: {
			if(lookupData.hexIndex < 0 || (unsigned)lookupData.hexIndex >= lookupData.system->hexes.size())
				return 0.0;
			const Design * design = lookupData.design;
			vec2u hex = lookupData.system->hexes[lookupData.hexIndex];
			double count = 0;
			for(unsigned d = 0; d < 6; ++d) {
				vec2u pos = hex;
				if(!design->hull->active.advance(pos.x, pos.y, HexGridAdjacency(d)))
					continue;
				if(!design->hull->active.get(pos))
					continue;
				int sysId = design->grid.get(pos);
				if((unsigned)sysId >= design->subsystems.size())
					continue;
				if(design->subsystems[sysId].type->index != index)
					continue;
				count += 1.0;
			}
			return count;
		}
	}
	return 0.0;
}

void Subsystem::init(const SubsystemDef& Def)
{
	type = &Def;
	unsigned effCount = Def.effects.size();
	effects.resize(effCount);
	for(unsigned i = 0; i < effCount; ++i)
		effects[i].type = Def.effects[i].type;

	unsigned efftrCount = Def.effectors.size();
	effectors = (Effector*)malloc(efftrCount * sizeof(Effector));
	for(unsigned i = 0; i < efftrCount; ++i) {
		new(&effectors[i]) Effector(*Def.effectors[i].type);
		effectors[i].enabled = Def.effectors[i].enabled;
		effectors[i].effectorIndex = i;
		effectors[i].skinIndex = Def.effectors[i].skinIndex;
	}

	defaults = new BasicType[Def.states.size()];
}

Subsystem::Subsystem()
	: type(nullptr), exteriorHexes(0), hasErrors(false), variables(0), hexVariables(0),
		inDesign(nullptr), index(0), defaults(nullptr), effectors(nullptr)
{
}

Subsystem::Subsystem(const SubsystemDef& Def)
	: type(nullptr), exteriorHexes(0), hasErrors(false), variables(0), hexVariables(0),
		inDesign(nullptr), index(0), defaults(nullptr), effectors(nullptr)
{
	init(Def);
}

void Subsystem::skinEffectors(Empire& emp) {
	if(emp.effectorSkin.empty())
		return;
	unsigned efftrCount = type->effectors.size();
	for(unsigned i = 0; i < efftrCount; ++i) {
		auto& efftr = effectors[i];

		std::string ident = type->effectors[i].skinName;
		if(!ident.empty())
			ident += "/";
		ident += emp.effectorSkin;

		auto it = efftr.type.skinNames.find(ident);
		if(it != efftr.type.skinNames.end())
			efftr.skinIndex = it->second;
	}
}

void SubsystemDef::ModifyStage::applyVariables(Subsystem* sys) const {
	foreach(v, variables) {
		int localIndex = sys->type->variableIndices[v->first];
		Formula* formula = v->second;

		if(formula)
			sys->variables[localIndex] = (float)formula->evaluate(&formulaVariable, &lookupData, &formulaIndex);
	}
}

void SubsystemDef::ModifyStage::applyHexVariables(Subsystem* sys, int hexIndex) const {
	foreach(v, hexVariables) {
		int localIndex = sys->type->hexVariableIndices[v->first];
		localIndex += hexIndex * sys->type->hexVariables.size();
		Formula* formula = v->second;

		if(formula)
			sys->hexVariables[localIndex] = (float)formula->evaluate(&formulaVariable, &lookupData, &formulaIndex);
	}
}

void SubsystemDef::ModifyStage::applyShipVariables(Design* dsg, Subsystem* sys) const {
	foreach(v, shipVariables) {
		int index = v->first;
		Formula* formula = v->second;

		if(formula)
			dsg->shipVariables[index] = (float)formula->evaluate(&formulaVariable, &lookupData, &formulaIndex);
	}
}

struct RunStage {
	int priority;
	int amount;
	const SubsystemDef::ModifyStage* stage;
	float args[MODIFY_STAGE_MAXARGS];

	RunStage(int p, int a, const SubsystemDef::ModifyStage* s)
		: priority(p), amount(a), stage(s) {
	}

	RunStage(int a, const SubsystemDef::AppliedStage& as)
		: priority(as.stage->stage), amount(a), stage(as.stage) {

		for(unsigned i = 0; i < MODIFY_STAGE_MAXARGS; ++i) {
			if(as.formulas[i])
				args[i] = (float)as.formulas[i]->evaluate(&formulaVariable, &lookupData, &formulaIndex);
			else
				args[i] = as.arguments[i];
		}
	}

	bool operator<(const RunStage& other) const {
		return priority < other.priority;
	}
};

void applyShipModifier(const SubsystemDef* type, SubsystemDef::ShipModifier& mod, std::vector<RunStage>& modStages) {
	auto fnd = type->modifierIds.find(mod.modifyName);
	if(fnd == type->modifierIds.end())
		return;
	if(!conditionMatches(type, mod.conditions))
		return;
	SubsystemDef::AppliedStage applied;
	for(unsigned i = 0; i < MODIFY_STAGE_MAXARGS; ++i)
		applied.arguments[i] = mod.stage.arguments[i];
	applied.stage = fnd->second;
	modStages.push_back(RunStage(1, applied));
}

void Subsystem::initVariables(Design* design) {
	//Make sure the lookup data matches
	lookupData.design = design;
	lookupData.system = this;
	lookupData.hexIndex = -1;

	//Get subsystem data from empire
	Empire::SubsystemData* ssdata = 0;
	if(design->owner) {
		ssdata = design->owner->getSubsystemData(type);

		//Add an error if this subsystem is not unlocked
		if(!ssdata || !ssdata->unlocked) {
			std::string errMsg = format(devices.locale.localize("ERROR_NOT_UNLOCKED").c_str(), type->name);
			design->errors.push_back(DesignError(true, errMsg, this));
			hasErrors = true;
		}
	}

	//Hold a priority queue of considered modify stages
	std::vector<RunStage> modStages;

	//Evaluate variables
	variables = new float[type->variables.size()];
	baseVariables = new float[type->variables.size()];
	memset(variables, 0, sizeof(float) * type->variables.size());
	memset(baseVariables, 0, sizeof(float) * type->variables.size());

	//Do modify stages from modules
	unsigned modCnt = type->modules.size();
	for(unsigned i = 0; i < modCnt; ++i) {
		if(moduleCounts[i] > 0) {
			auto& mod = *type->modules[i];

			//Unique inline modifiers
			foreach(it, mod.uniqueModifiers)
				modStages.push_back(RunStage(it->stage, 1, &*it));

			//Unique applied stages
			foreach(it, mod.uniqueAppliedStages)
				modStages.push_back(RunStage(1, *it));

			//Inline modifiers
			foreach(it, mod.modifiers)
				modStages.push_back(RunStage(it->stage, moduleCounts[i], &*it));

			//Applied stages
			foreach(it, mod.appliedStages)
				modStages.push_back(RunStage(moduleCounts[i], *it));
		}
	}

	//Ship modifiers
	foreach(it, design->modifiers)
		applyShipModifier(type, *it, modStages);

	//Do modify stages from empire
	if(ssdata) {
		foreach(it, ssdata->stages)
			modStages.push_back(RunStage(1, it->second));
	}

	std::sort(modStages.begin(), modStages.end());

	for(unsigned i = 0; i < type->variables.size(); ++i) {
		auto* formula = type->variables[i].formula;
		if(formula)
			variables[i] = (float)formula->evaluate(&formulaVariable, &lookupData, &formulaIndex);
		else
			variables[i] = 0;
		baseVariables[i] = variables[i];

		foreach(it, modStages) {
			RunStage& rs = *it;

			bool hasArgs = false;
			foreach(v, rs.stage->variables) {
				unsigned localIndex = type->variableIndices[v->first];
				Formula* formula = v->second;

				if(localIndex == i && formula) {
					if(!hasArgs) {
						memcpy(&lookupData.args, &rs.args, sizeof(rs.args));
						hasArgs = true;
					}
					for(int repeats = 0; repeats < rs.amount; ++repeats)
						variables[localIndex] = (float)formula->evaluate(&formulaVariable, &lookupData, &formulaIndex);
				}
			}
		}
	}

	//Evaluate ship variables
	for(unsigned i = 0; i < type->shipVariables.size(); ++i) {
		auto* formula = type->shipVariables[i].formula;
		int index = type->shipVariables[i].index;
		if(formula)
			design->shipVariables[index] = (float)formula->evaluate(&formulaVariable, &lookupData, &formulaIndex);
	}

	//Check if all modules are unlocked
	for(unsigned i = 0; i < modCnt; ++i) {
		if(moduleCounts[i] > 0) {
			auto& mod = *type->modules[i];

			if(ssdata) {
				if(ssdata->modulesUnlocked.size() <= (unsigned)mod.index || !ssdata->modulesUnlocked[mod.index]) {
					std::string errMsg = format(devices.locale.localize("ERROR_MODULE_NOT_UNLOCKED").c_str(), mod.name);
					design->errors.push_back(DesignError(true, errMsg, this, &mod));
					hasErrors = true;
				}
			}
		}
	}

	//Run all the modify stages
	foreach(it, modStages) {
		RunStage& rs = *it;
		memcpy(&lookupData.args, &rs.args, sizeof(rs.args));
		for(int i = 0; i < rs.amount; ++i)
			rs.stage->applyShipVariables(design, this);
	}

	//Dump
	//for(unsigned j = 0; j < type->variables.size(); ++j) {
		//printf("%s.%s = %g\n", type->id.c_str(),
				//type->variables[j].name.c_str(), variables[j]);
	//}

	//Recompute mod stages without hex-specific ones
	modStages.clear();
	for(unsigned i = 0; i < modCnt; ++i) {
		if(moduleCounts[i] > 0) {
			auto& mod = *type->modules[i];

			//Unique applied stages
			foreach(it, mod.uniqueAppliedStages)
				if(!it->stage->hexVariables.empty())
					modStages.push_back(RunStage(1, *it));

			//Applied stages
			foreach(it, mod.appliedStages)
				if(!it->stage->hexVariables.empty())
					modStages.push_back(RunStage(moduleCounts[i], *it));
		}
	}

	//Ship modifiers
	foreach(it, design->modifiers)
		applyShipModifier(type, *it, modStages);

	//Do modify stages from empire
	if(ssdata) {
		foreach(it, ssdata->stages)
			if(!it->second.stage->hexVariables.empty())
				modStages.push_back(RunStage(1, it->second));
	}

	std::sort(modStages.begin(), modStages.end());

	//Evaluate hex variables
	unsigned varCnt = type->hexVariables.size();
	unsigned hexCnt = hexes.size();
	hexVariables = new float[varCnt * hexCnt];
	hexBaseVariables = new float[varCnt * hexCnt];
	hexAdjacentModifiers.resize(hexCnt);
	hexEffects.resize(hexes.size());
	bool foundCore = false;

	for(unsigned i = 0; i < hexCnt; ++i) {
		unsigned base = varCnt * i;
		lookupData.hexIndex = i;

		//Cache the position of the core
		if(type->hasCore && modules[i] == type->coreModule) {
			core = hexes[i];
			foundCore = true;
		}

		//Initialize all the default formulas for a hex
		for(unsigned j = 0; j < varCnt; ++j) {
			auto* formula = type->hexVariables[j].formula;
			if(formula)
				hexVariables[base + j] = (float)formula->evaluate(&formulaVariable, &lookupData, &formulaIndex);
			else
				hexVariables[base + j] = 0;
			hexBaseVariables[base + j] = hexVariables[base + j];
		}

		//Add the modify stages
		auto* mod = modules[i];
		foreach(it, mod->uniqueModifiers) {
			if(!it->hexVariables.empty()) {
				it->applyHexVariables(this, i);
			}
		}
		foreach(it, mod->modifiers) {
			if(!it->hexVariables.empty()) {
				it->applyHexVariables(this, i);
			}
		}
		foreach(it, mod->hexAppliedStages) {
			if(!it->stage->hexVariables.empty()) {
				RunStage rs(1, *it);

				memcpy(&lookupData.args, &rs.args, sizeof(float) * MODIFY_STAGE_MAXARGS);
				rs.stage->applyHexVariables(this, i);
			}
		}

		//Add adjacent modifiers
		foreach(it, mod->adjacentModifiers) {
			SubsystemDef::ShipModifier mod;
			mod.modifyName = it->modifyName;
			mod.conditions = it->conditions;
			for(unsigned j = 0; j < MODIFY_STAGE_MAXARGS; ++j) {
				if(it->stage.formulas[j])
					mod.stage.arguments[j] = it->stage.formulas[j]->evaluate(&formulaVariable, &lookupData, &formulaIndex);
			}

			hexAdjacentModifiers[i].push_back(mod);
		}

		//Run the modify stages
		foreach(it, modStages) {
			RunStage& rs = *it;

			memcpy(&lookupData.args, &rs.args, sizeof(float) * MODIFY_STAGE_MAXARGS);
			for(int j = 0; j < rs.amount; ++j)
				rs.stage->applyHexVariables(this, i);
		}

		//Run dependent variables again
		for(unsigned j = 0; j < varCnt; ++j) {
			if(!type->hexVariables[j].dependent)
				continue;

			auto* formula = type->hexVariables[j].formula;
			if(formula)
				hexVariables[base + j] = (float)formula->evaluate(&formulaVariable, &lookupData, &formulaIndex);
		}

		//Dump
		//for(unsigned j = 0; j < varCnt; ++j) {
			//printf("%s[%d,%d].%s = %g\n", type->id.c_str(),
					//hexes[i].x, hexes[i].y,
					//type->hexVariables[j].name.c_str(),
					//hexVariables[base + j]);
		//}
	}

	//Re-evaluate variables marked as dependent to get the correct values
	for(unsigned i = 0; i < type->variables.size(); ++i) {
		if(!type->variables[i].dependent)
			continue;

		auto* formula = type->variables[i].formula;
		if(formula)
			variables[i] = (float)formula->evaluate(&formulaVariable, &lookupData, &formulaIndex);
	}

	//Add ship modifiers
	foreach(it, type->shipModifiers) {
		SubsystemDef::ShipModifier mod;
		mod.modifyName = it->modifyName;
		mod.conditions = it->conditions;
		for(unsigned i = 0; i < MODIFY_STAGE_MAXARGS; ++i) {
			if(it->stage.formulas[i])
				mod.stage.arguments[i] = it->stage.formulas[i]->evaluate(&formulaVariable, &lookupData, &formulaIndex);
		}

		design->modifiers.push_back(mod);
	}

	//Add adjacent modifiers
	foreach(it, type->adjacentModifiers) {
		SubsystemDef::ShipModifier mod;
		mod.modifyName = it->modifyName;
		mod.conditions = it->conditions;
		for(unsigned i = 0; i < MODIFY_STAGE_MAXARGS; ++i) {
			if(it->stage.formulas[i])
				mod.stage.arguments[i] = it->stage.formulas[i]->evaluate(&formulaVariable, &lookupData, &formulaIndex);
		}

		adjacentModifiers.push_back(mod);
	}

	//Add an error if this subsystem should have a core, but doesn't
	if(type->hasCore && !foundCore) {
		std::string errMsg = format(devices.locale.localize("ERROR_NO_CORE").c_str(), type->name);

		design->errors.push_back(DesignError(true, errMsg, this));
		hasErrors = true;
	}

	//Add an error if we needed an exterior core, but don't
	if(type->hasCore && foundCore && type->exteriorCore && !design->hull->isExterior(core)) {
		std::string errMsg = format(devices.locale.localize("ERROR_NEEDS_EXTERIOR_CORE").c_str(), type->name);

		design->errors.push_back(DesignError(true, errMsg, this, 0, core));
		hasErrors = true;
	}

	//Add an error if any required modules are not present
	for(unsigned i = 0, modCnt = type->modules.size(); i < modCnt; ++i) {
		auto* mod = type->modules[i];
		if(mod->required && moduleCounts[i] == 0 && mod != type->coreModule) {
			std::string errMsg = format(devices.locale.localize("ERROR_REQUIRED_MODULE").c_str(), type->name, mod->name);

			design->errors.push_back(DesignError(true, errMsg, this, mod));
			hasErrors = true;
		}
		if(mod->unique && moduleCounts[i] > 1) {
			std::string errMsg = format(devices.locale.localize("ERROR_UNIQUE_MODULE").c_str(), type->name, mod->name);

			design->errors.push_back(DesignError(true, errMsg, this, mod));
			hasErrors = true;
		}
	}

	//Add an error if we can't use this subsystem on this hull
	if(!type->canUseOn(design->hull)) {
		std::string errMsg = format(devices.locale.localize("ERROR_INVALID_HULL").c_str(), type->name);
		design->errors.push_back(DesignError(true, errMsg, this));
		hasErrors = true;
	}
}

void Subsystem::applyAdjacencies(Design* design) {
	lookupData.design = design;
	lookupData.system = this;

	std::vector<RunStage> modStages;

	for(size_t n = 0, hexCnt = hexes.size(); n < hexCnt; ++n) {
		vec2u hex = hexes[n];
		lookupData.hexIndex = n;

		if(!design->hull->active.valid(hex))
			continue;

		//Check all adjacent hexes
		for(unsigned i = 0; i < 6; ++i) {
			vec2u pos = hex;
			if(!design->hull->active.advance(pos.x, pos.y, HexGridAdjacency(i)))
				continue;
			if(!design->hull->active.get(pos))
				continue;

			int sysId = design->grid.get(pos);
			if((unsigned)sysId >= design->subsystems.size())
				continue;

			auto& otherSys = design->subsystems[sysId];

			int hexId = design->hexIndex.get(pos);
			if((unsigned)hexId >= otherSys.hexes.size())
				continue;

			for(size_t j = 0, jcnt = otherSys.adjacentModifiers.size(); j < jcnt; ++j)
				applyShipModifier(this->type, otherSys.adjacentModifiers[j], modStages);

			for(size_t j = 0, jcnt = otherSys.hexAdjacentModifiers[hexId].size(); j < jcnt; ++j)
				applyShipModifier(this->type, otherSys.hexAdjacentModifiers[hexId][j], modStages);
		}

		std::sort(modStages.begin(), modStages.end());

		//Run all the modify stages
		foreach(it, modStages) {
			RunStage& rs = *it;

			memcpy(&lookupData.args, &rs.args, sizeof(rs.args));
			for(int i = 0; i < rs.amount; ++i) {
				rs.stage->applyVariables(this);
				rs.stage->applyHexVariables(this, n);
			}
		}
		modStages.clear();
	}
}

extern double effVariable(void* effector, const std::string* name);
SubsystemDef::HookDesc::HookDesc(const std::string& str) {
	if(!funcSplit(str, name, str_args))
		name = str;
	formulas.resize(str_args.size());
	argValues.resize(str_args.size());
	for(size_t i = 0, cnt = str_args.size(); i < cnt; ++i) {
		formulas[i] = nullptr;
		argValues[i] = 0.0;
	}
}
void Subsystem::initEffects(Design* design) {
	//Make sure the lookup data matches
	lookupData.design = design;
	lookupData.system = this;
	lookupData.hexIndex = -1;

	//Evaluate effect values
	for(unsigned i = 0; i < type->effects.size(); ++i) {
		for(unsigned j = 0; j < type->effects[i].values.size(); ++j) {
			if(auto* formula = type->effects[i].values[j])
				effects[i].values[j] = formula->evaluate(&formulaVariable, &lookupData, &formulaIndex);
			else if(effects[i].type->values[j].defaultValue)
				effects[i].values[j] = effects[i].type->values[j].defaultValue->evaluate();
		}
	}

	//Evaluate effects from modules
	for(unsigned i = 0; i < hexes.size(); ++i) {
		auto* module = modules[i];
		if(module->effects.empty())
			continue;
		lookupData.hexIndex = i;

		for(unsigned n = 0; n < module->effects.size(); ++n) {
			auto& def = module->effects[n];
			Effect eff(def.type);
			for(unsigned j = 0; j < def.values.size(); ++j) {
				if(auto* formula = def.values[j])
					eff.values[j] = formula->evaluate(&formulaVariable, &lookupData, &formulaIndex);
				else if(eff.type->values[j].defaultValue)
					eff.values[j] = eff.type->values[j].defaultValue->evaluate();
			}

			unsigned id = effects.size();
			effects.push_back(eff);
			hexEffects[i].push_back(id);
		}
	}
	lookupData.hexIndex = -1;

	for(unsigned i = 0; i < type->effectors.size(); ++i) {
		//Evaluate effector values
		for(unsigned j = 0; j < type->effectors[i].values.size(); ++j) {
			if(auto* formula = type->effectors[i].values[j])
				effectors[i].values[j] = formula->evaluate(&formulaVariable, &lookupData, &formulaIndex);
			else if(effectors[i].type.values[j].defaultValue)
				effectors[i].values[j] = effectors[i].type.values[j].defaultValue->evaluate(effVariable, &effectors[i]);
		}

		effectors[i].initValues();

		//Set relative positions of the effectors
		effectors[i].setRelativePosition(core, design->hull, direction);

		//Deal with hex-limited angles
		if(type->hexLimitArc && design->hull->active.valid(core) && !design->hasTag(overrideHexArcLimitTag)) {
			auto& eff = effectors[i];

			//Make sure the turret angle is within bounds
			vec2d flatAngle(eff.turretAngle.x, -eff.turretAngle.z);
			double rad = flatAngle.radians();
			unsigned dir = HexGrid<>::AdjacencyFromRadians(rad);

			if(!design->hull->isExteriorInDirection(core, dir)) {
				double diff = rad - HexGrid<>::RadiansFromAdjacency(HexGridAdjacency(dir));
				if(diff >= twopi / 6.0 * 0.5 * 0.99)
					dir = (dir+1)%6;
				else if(diff <= -twopi / 6.0 * 0.5 * 0.99)
					dir = (6+dir-1)%6;

				if(!design->hull->isExteriorInDirection(core, dir)) {
					std::string errMsg = format(devices.locale.localize("ERROR_HEX_LIMIT_ARC").c_str(), type->name);
					design->errors.push_back(DesignError(false, errMsg, this));
					hasErrors = true;
					eff.fireArc = -1.0;
				}
			}

			//Move the turret angle to the center position so we scrunch the firing arc
			if(eff.fireArc > 0) {
				double specRad = HexGrid<>::RadiansFromAdjacency(HexGridAdjacency(dir));
				double minRad = specRad - (twopi / 12.0);
				double arc;
				bool shouldChange = false;

				arc = eff.fireArc - (rad - minRad);
				for(unsigned n = 1; n <= 3 && arc > 0; ++n) {
					unsigned chkDir = (6 + dir - n) % 6;
					if(!design->hull->isExteriorInDirection(core, chkDir)) {
						shouldChange = true;
						minRad -= std::min(twopi / 48.0, arc);
						break;
					}
					minRad -= std::min(twopi / 6.0, arc);
					arc -= twopi / 6.0;
				}

				double maxRad = specRad + (twopi / 12.0);
				arc = eff.fireArc - (maxRad - rad);
				for(unsigned n = 1; n <= 3 && arc > 0; ++n) {
					unsigned chkDir = (dir + n) % 6;
					if(!design->hull->isExteriorInDirection(core, chkDir)) {
						shouldChange = true;
						maxRad += std::min(twopi / 48.0, arc);
						break;
					}
					maxRad += std::min(twopi / 6.0, arc);
					arc -= twopi / 6.0;
				}

				if(shouldChange) {
					double arcRad = (maxRad - minRad) * 0.5;
					eff.fireArc = std::min(arcRad, eff.fireArc);

					vec2d newPos(1.0, 0.0);
					newPos.rotate(minRad + (arcRad - eff.fireArc) * 0.5 + arcRad);

					eff.turretAngle.x = newPos.x;
					eff.turretAngle.z = -newPos.y;
				}
			}
		}

		//Set relative size of the effector
		effectors[i].relativeSize = 3.0 * sqrt((double)hexes.size() / (double)design->hull->activeCount);
	}

	//Evaluate states
	for(unsigned i = 0; i < type->states.size(); ++i) {
		double value = 0;
		if(auto* formula = type->states[i].formula)
			value = formula->evaluate(&formulaVariable, &lookupData, &formulaIndex);
		defaults[i].type = type->states[i].type;
		switch(type->states[i].type) {
			default:
			case BT_Double:
				defaults[i].decimal = value;
			break;
			case BT_Int:
				defaults[i].integer = (int)value;
			break;
			case BT_Bool:
				defaults[i].boolean = (bool)(value != 0.0);
			break;
		}
	}

	//Initialize hooks
	for(size_t i = 0, cnt = type->hooks.size(); i < cnt; ++i)
		addHook(design, type->hooks[i]);
	for(size_t i = 0, cnt = modules.size(); i < cnt; ++i) {
		auto* module = modules[i];
		if(module) {
			for(size_t n = 0, ncnt = module->hooks.size(); n < ncnt; ++n)
				addHook(design, module->hooks[n]);
		}
	}
}

void Subsystem::addHook(Design* design, const SubsystemDef::HookDesc& hook) {
	if(devices.scripts.server == devices.scripts.cache_shadow)
		return;
	std::vector<std::string> parts;
	split(hook.name, parts, "::");

	asITypeInfo* cls = nullptr;
	if(parts.size() == 1)
		cls = devices.scripts.server->getClass("subsystem_effects", parts[0].c_str());
	else if(parts.size() == 2)
		cls = devices.scripts.server->getClass(parts[0].c_str(), parts[1].c_str());
	if(cls == nullptr)
		return;

	asIScriptObject* obj = (asIScriptObject*)devices.scripts.server->engine->CreateScriptObject(cls);
	if(obj == nullptr)
		return;

	for(unsigned i = 0, cnt = hook.formulas.size(); i < cnt; ++i) {
		if(hook.formulas[i])
			hook.argValues[i] = hook.formulas[i]->evaluate(&formulaVariable, &lookupData, &formulaIndex);
		else
			hook.argValues[i] = 0.0;
	}

	auto call = devices.scripts.server->call(ScriptInitFunction);
	bool retVal = false;
	call.setObject(obj);
	call.push(design);
	call.push(this);
	call.push(&hook.str_args);
	call.push(&hook.argValues);
	call.call(retVal);

	if(retVal)
		hookClasses.push_back(obj);
	else
		obj->Release();
}

void Subsystem::evaluatePost(Design* design) {
	//Make sure the lookup data matches
	lookupData.design = design;
	lookupData.system = this;
	lookupData.hexIndex = -1;

	//Do any post-ship modifiers
	std::vector<RunStage> stages;
	foreach(it, type->postModifiers) {
		SubsystemDef::ShipModifier mod;
		mod.modifyName = it->modifyName;
		mod.conditions = it->conditions;
		for(unsigned i = 0; i < MODIFY_STAGE_MAXARGS; ++i) {
			if(it->stage.formulas[i])
				mod.stage.arguments[i] = it->stage.formulas[i]->evaluate(&formulaVariable, &lookupData, &formulaIndex);
		}

		applyShipModifier(type, mod, stages);
	}

	std::sort(stages.begin(), stages.end());

	//Run all the modify stages
	foreach(it, stages) {
		memcpy(&lookupData.args, it->args, sizeof(it->args));
		for(int i = 0; i < it->amount; ++i)
			it->stage->applyVariables(this);
	}

	foreach(it, stages) {
		memcpy(&lookupData.args, it->args, sizeof(it->args));
		for(int i = 0; i < it->amount; ++i)
			it->stage->applyShipVariables(design, this);
	}

	unsigned hexCnt = hexes.size();
	for(unsigned i = 0; i < hexCnt; ++i) {
		lookupData.hexIndex = i;

		foreach(it, stages) {
			memcpy(&lookupData.args, it->args, sizeof(it->args));
			for(int n = 0; n < it->amount; ++n)
				it->stage->applyHexVariables(this, i);
		}
	}
}

void Subsystem::evaluateAsserts(Design* design) {
	//Make sure the lookup data matches
	lookupData.design = design;
	lookupData.system = this;
	lookupData.hexIndex = -1;

	auto checkAssert = [](Subsystem* sys, Design* design, const SubsystemDef::Assert& ass) {
		if(!ass.formula)
			return;

		double val = ass.formula->evaluate(&formulaVariable, &lookupData, &formulaIndex);
		if(val <= 0.0) {
			//Check uniqueness
			std::string msg = format(ass.message.c_str(), sys->type->name.c_str());
			if(ass.unique) {
				bool duplicate = false;
				foreach(e, design->errors) {
					if(e->fatal != ass.fatal)
						continue;
					if(e->text != msg)
						continue;
					duplicate = true;
					break;
				}

				if(duplicate)
					return;

				design->errors.push_back(DesignError(
					ass.fatal, msg, 0, 0));
				sys->hasErrors = true;
			}
			else {
				design->errors.push_back(DesignError(
					ass.fatal, msg, sys, 0));
				sys->hasErrors = true;
			}
		}
	};

	//Check any assertion errors
	foreach(it, type->asserts) {
		const SubsystemDef::Assert& ass = *it;
		checkAssert(this, design, ass);
	}

	//Check hex asserts
	for(unsigned i = 0, hexCount = (unsigned)hexes.size(); i < hexCount; ++i) {
		lookupData.hexIndex = i;
		foreach(it, modules[i]->asserts) {
			const SubsystemDef::Assert& ass = *it;
			checkAssert(this, design, ass);
		}

		if(modules[i]->onCheckErrors(design, this, hexes[i]))
			hasErrors = true;
	}

	//Add any errors from the script check
	if(type->onCheckErrors(design, this))
		hasErrors = true;
}

void Subsystem::ownerChange(EffectEvent& event, Empire* prevEmpire, Empire* newEmpire) const {
	for(unsigned i = 0; i < effects.size(); ++i)
		effects[i].ownerChange(event, prevEmpire, newEmpire);

	if(!hookClasses.empty()) {
		SubsystemEvent evt;
		evt.obj = event.obj;
		evt.subsystem = this;
		evt.blueprint = nullptr;
		evt.design = inDesign;
		evt.data = nullptr;
		evt.efficiency = event.efficiency;
		evt.partiality = event.partiality;

		if(evt.obj != nullptr && evt.obj->type->blueprintOffset != 0)
			evt.blueprint = (Blueprint*)(((size_t)evt.obj) + evt.obj->type->blueprintOffset);

		for(size_t i = 0, cnt = hookClasses.size(); i < cnt; ++i) {
			if(evt.blueprint != nullptr)
				evt.data = evt.blueprint->data[dataOffset+i];

			auto cl = devices.scripts.server->call(ScriptHookFunctions[EH_Owner_Change]);
			cl.setObject(hookClasses[i]);
			cl.push(&evt);
			cl.push(prevEmpire);
			cl.push(newEmpire);
			cl.call();
		}
	}
}

void Subsystem::call(EffectHook hook, EffectEvent& event) const {
	for(unsigned i = 0; i < effects.size(); ++i)
		effects[i].call(hook, event);

	if(!hookClasses.empty()) {
		SubsystemEvent evt;
		evt.obj = event.obj;
		evt.subsystem = this;
		evt.design = inDesign;
		evt.blueprint = nullptr;
		evt.data = nullptr;
		evt.efficiency = event.efficiency;
		evt.partiality = event.partiality;

		if(evt.obj != nullptr && evt.obj->type->blueprintOffset != 0)
			evt.blueprint = (Blueprint*)(((size_t)evt.obj) + evt.obj->type->blueprintOffset);

		for(size_t i = 0, cnt = hookClasses.size(); i < cnt; ++i) {
			if(evt.blueprint != nullptr)
				evt.data = evt.blueprint->data[dataOffset+i];

			auto cl = devices.scripts.server->call(ScriptHookFunctions[hook]);
			cl.setObject(hookClasses[i]);
			cl.push(&evt);
			cl.call();
		}
	}
}

void Subsystem::save(EffectEvent& event, SaveMessage& msg) const {
	if(!hookClasses.empty()) {
		SubsystemEvent evt;
		evt.obj = event.obj;
		evt.subsystem = this;
		evt.design = inDesign;
		evt.blueprint = nullptr;
		evt.data = nullptr;
		evt.efficiency = event.efficiency;
		evt.partiality = event.partiality;

		if(evt.obj != nullptr && evt.obj->type->blueprintOffset != 0)
			evt.blueprint = (Blueprint*)(((size_t)evt.obj) + evt.obj->type->blueprintOffset);

		for(size_t i = 0, cnt = hookClasses.size(); i < cnt; ++i) {
			if(evt.blueprint != nullptr)
				evt.data = evt.blueprint->data[dataOffset+i];

			auto cl = devices.scripts.server->call(ScriptHookFunctions[EH_Save]);
			cl.setObject(hookClasses[i]);
			cl.push(&evt);
			cl.push(&msg);
			cl.call();
		}
	}
}

void Subsystem::load(EffectEvent& event, SaveMessage& msg) const {
	if(!hookClasses.empty()) {
		SubsystemEvent evt;
		evt.obj = event.obj;
		evt.subsystem = this;
		evt.design = inDesign;
		evt.blueprint = nullptr;
		evt.data = nullptr;
		evt.efficiency = event.efficiency;
		evt.partiality = event.partiality;

		if(evt.obj != nullptr && evt.obj->type->blueprintOffset != 0)
			evt.blueprint = (Blueprint*)(((size_t)evt.obj) + evt.obj->type->blueprintOffset);

		for(size_t i = 0, cnt = hookClasses.size(); i < cnt; ++i) {
			if(evt.blueprint != nullptr && dataOffset+i < inDesign->dataCount)
				evt.data = evt.blueprint->data[dataOffset+i];

			auto cl = devices.scripts.server->call(ScriptHookFunctions[EH_Load]);
			cl.setObject(hookClasses[i]);
			cl.push(&evt);
			cl.push(&msg);
			cl.call();
		}
	}
}

void Subsystem::tick(EffectEvent& event) const {
	//Tick Effects
	EffectStatus status = event.status;
	for(unsigned i = 0; i < effects.size(); ++i) {
		effects[i].call(EH_Tick, event);

		//Cancel when any effect suspends or continues
		if(status == ES_Suspended) {
			if(event.status != ES_Suspended)
				return;
		}
		else {
			if(event.status == ES_Suspended)
				return;
		}
	}

	if(!hookClasses.empty() && event.status == ES_Active) {
		SubsystemEvent evt;
		evt.obj = event.obj;
		evt.subsystem = this;
		evt.design = inDesign;
		evt.blueprint = nullptr;
		evt.data = nullptr;
		evt.efficiency = event.efficiency;
		evt.partiality = event.partiality;

		if(evt.obj != nullptr && evt.obj->type->blueprintOffset != 0)
			evt.blueprint = (Blueprint*)(((size_t)evt.obj) + evt.obj->type->blueprintOffset);

		for(size_t i = 0, cnt = hookClasses.size(); i < cnt; ++i) {
			if(evt.blueprint != nullptr)
				evt.data = evt.blueprint->data[dataOffset+i];

			auto cl = devices.scripts.server->call(ScriptHookFunctions[EH_Tick]);
			cl.setObject(hookClasses[i]);
			cl.push(&evt);
			cl.push(event.time);
			cl.call();
		}
	}
}

DamageEventStatus Subsystem::damage(DamageEvent& event, const vec2u& position) const {
	for(unsigned i = 0; i < type->effects.size(); ++i) {
		switch(effects[i].damage(event, position)) {
			case DE_Continue:
			break;
			case DE_SkipHex:
				return DE_SkipHex;
			case DE_EndDamage:
				return DE_EndDamage;
		}
	}

	if(inDesign != nullptr && inDesign->hull->active.valid(position)) {
		unsigned hexIndex = (unsigned)inDesign->hexIndex[position];
		if(hexIndex < hexEffects.size()) {
			auto& hexEffs = hexEffects[hexIndex];
			for(unsigned i = 0; i < hexEffs.size(); ++i) {
				switch(effects[hexEffs[i]].damage(event, position)) {
					case DE_Continue:
					break;
					case DE_SkipHex:
						return DE_SkipHex;
					case DE_EndDamage:
						return DE_EndDamage;
				}
			}
		}
	}

	if(!hookClasses.empty()) {
		SubsystemEvent evt;
		evt.obj = event.obj;
		evt.subsystem = this;
		evt.design = inDesign;
		evt.blueprint = nullptr;
		evt.data = nullptr;

		if(evt.obj != nullptr && evt.obj->type->blueprintOffset != 0)
			evt.blueprint = (Blueprint*)(((size_t)evt.obj) + evt.obj->type->blueprintOffset);

		for(size_t i = 0, cnt = hookClasses.size(); i < cnt; ++i) {
			if(evt.blueprint != nullptr)
				evt.data = evt.blueprint->data[dataOffset+i];

			auto cl = devices.scripts.server->call(ScriptHookFunctions[EH_Damage]);
			unsigned retVal = 0;
			cl.setObject(hookClasses[i]);
			cl.push(&evt);
			cl.push(&event);
			cl.push(&position);
			cl.call(retVal);

			switch(retVal) {
				case DE_Continue:
				break;
				case DE_SkipHex:
					return DE_SkipHex;
				case DE_EndDamage:
					return DE_EndDamage;
			}
		}
	}
	return DE_Continue;
}

bool Subsystem::hasGlobalDamage() const {
	if(!hookClasses.empty())
		return true;

	for(unsigned i = 0; i < effects.size(); ++i) {
		if(effects[i].type->hooks[EH_GlobalDamage])
			return true;
	}
	return false;
}

DamageEventStatus Subsystem::globalDamage(DamageEvent& event, vec2u& position, vec2d& endPoint) const {
	for(unsigned i = 0; i < effects.size(); ++i) {
		switch(effects[i].globalDamage(event, position, endPoint)) {
			case DE_Continue:
			break;
			case DE_SkipHex:
				return DE_SkipHex;
			case DE_EndDamage:
				return DE_EndDamage;
		}
	}

	if(!hookClasses.empty()) {
		SubsystemEvent evt;
		evt.obj = event.obj;
		evt.subsystem = this;
		evt.design = inDesign;
		evt.blueprint = nullptr;
		evt.data = nullptr;

		if(evt.obj != nullptr && evt.obj->type->blueprintOffset != 0)
			evt.blueprint = (Blueprint*)(((size_t)evt.obj) + evt.obj->type->blueprintOffset);

		for(size_t i = 0, cnt = hookClasses.size(); i < cnt; ++i) {
			if(evt.blueprint != nullptr)
				evt.data = evt.blueprint->data[dataOffset+i];

			auto cl = devices.scripts.server->call(ScriptHookFunctions[EH_GlobalDamage]);
			unsigned retVal = 0;
			cl.setObject(hookClasses[i]);
			cl.push(&evt);
			cl.push(&event);
			cl.push(&position);
			cl.push(&endPoint);
			cl.call(retVal);

			switch(retVal) {
				case DE_Continue:
				break;
				case DE_SkipHex:
					return DE_SkipHex;
				case DE_EndDamage:
					return DE_EndDamage;
			}
		}
	}
	return DE_Continue;
}

float* Subsystem::variable(int index) {
	if(index < 0)
		return 0;
	if((size_t)index >= type->variableIndices.size() || type->variableIndices[index] < 0)
		return 0;
	return &variables[type->variableIndices[index]];
}

const float* Subsystem::variable(int index) const {
	//NOTE: Legit
	return ((Subsystem*)this)->variable(index);
}

float* Subsystem::hexVariable(int index, int hexIndex) {
	if(index < 0 || hexIndex < 0 || (unsigned)hexIndex >= hexes.size())
		return 0;
	if((size_t)index >= type->hexVariableIndices.size() || type->hexVariableIndices[index] < 0)
		return 0;
	int base = hexIndex * type->hexVariables.size();
	int localIndex = type->hexVariableIndices[index];
	return &hexVariables[base + localIndex];
}

const float* Subsystem::hexVariable(int index, int hexIndex) const {
	//NOTE: Legit
	return ((Subsystem*)this)->hexVariable(index, hexIndex);
}

void Subsystem::markConnected(HexGrid<bool>& grid, vec2u hex) {
	if(!grid.valid(hex) || grid[hex])
		return;
	grid[hex] = true;
	for(unsigned i = 0; i < 6; ++i) {
		vec2u pos = hex;
		if(grid.advance(pos, HexGridAdjacency(i))) {
			if(inDesign->grid[pos] == int(this->index))
				markConnected(grid, pos);
		}
	}
}

Subsystem::~Subsystem() {
	delete[] variables;
	delete[] hexVariables;
}

void Subsystem::init(SaveFile& file) {
	int typeID = file.readIdentifier(SI_Subsystem);
	type = getSubsystemDef(typeID);
	if(type == 0)
		throw SaveFileError("Subsystem definition does not exist");

	file >> core >> exteriorHexes >> stateOffset >> effectorOffset;
	file >> direction;
	if(file >= SFV_0008)
		file >> dataOffset;
	else
		dataOffset = 0;

	unsigned hexCount = file;
	hexes.resize(hexCount);
	file.read(hexes.data(), hexes.size() * sizeof(vec2u));
	hexEffects.resize(hexCount);

	if(file >= SFV_0010) {
		for(unsigned i = 0; i < hexCount; ++i) {
			unsigned cnt = file;
			hexEffects[i].resize(cnt);
			for(unsigned j = 0; j < cnt; ++j)
				file >> hexEffects[i][j];
		}
	}
	
	moduleCounts.resize(type->modules.size(), 0);

	unsigned moduleCount = file;
	modules.resize(moduleCount);
	for(unsigned i = 0; i < modules.size(); ++i) {
		int modIndex = -1;

		if(file >= SFV_0012) {
			int index = file.readIdentifier(SI_SubsystemModule);
			if(index >= 0 && index < (int)ModulesByID.size())
				modIndex = ModulesByID[index]->index;
		}
		else {
			int index = file;
			//Sorry, no actual way to do this nicely
			if(index == 0) {
				auto it = type->moduleIndices.find("Default");
				if(it != type->moduleIndices.end())
					modIndex = it->second;
			}
			else if(index == 1) {
				auto it = type->moduleIndices.find("Core");
				if(it != type->moduleIndices.end())
					modIndex = it->second;
			}
			else {
				auto it = type->moduleIndices.find("Bulkhead");
				if(it != type->moduleIndices.end())
					modIndex = it->second;
			}
		}

		if(modIndex < 0 || modIndex >= (int)type->modules.size())
			modIndex = type->defaultModule->index;
		modules[i] = type->modules[modIndex];
		moduleCounts[modIndex] += 1;
	}

	if(file >= SFV_0010) {
		unsigned cnt = file;
		effects.resize(cnt);
		for(unsigned i = 0; i < cnt; ++i) {
			effects[i].type = getEffectDefinition(file.readIdentifier(SI_Effect));
			file.read(effects[i].values, sizeof(double) * EFFECT_MAX_VALUES);
		}
	}
	else {
		effects.resize(type->effects.size());
		for(unsigned i = 0; i < type->effects.size(); ++i) {
			effects[i].type = type->effects[i].type;
			file.read(effects[i].values, sizeof(double) * effects[i].type->valueCount);
		}
	}

	effectors = (Effector*)malloc(type->effectors.size() * sizeof(Effector));
	for(unsigned i = 0; i < type->effectors.size(); ++i) {
		new(&effectors[i]) Effector(*type->effectors[i].type);

		Effector& effector = effectors[i];
		effector.effectorIndex = i;
		effector.load(file);
	}

	defaults = new BasicType[type->states.size()];
	file.read(defaults, sizeof(BasicType) * type->states.size());

	variables = new float[type->variables.size()]();
	baseVariables = new float[type->variables.size()]();

	hexVariables = new float[type->hexVariables.size() * hexCount]();
	hexBaseVariables = new float[type->hexVariables.size() * hexCount]();

	unsigned cnt = file;
	for(unsigned i = 0; i < cnt; ++i) {
		int globIndex = file.readIdentifier(SI_SubsystemVar);
		int index = -1;
		if((size_t)globIndex < type->variableIndices.size() && type->variableIndices[globIndex] >= 0)
			index = type->variableIndices[globIndex];

		if(index != -1) {
			file >> variables[index];
			file >> baseVariables[index];
		}
		else {
			file.read<float>();
			file.read<float>();
		}
	}

	unsigned varCnt = file;
	for(unsigned i = 0; i < varCnt; ++i) {
		int globIndex = file.readIdentifier(SI_HexVar);
		int index = -1;
		if((size_t)globIndex < type->hexVariableIndices.size() && type->hexVariableIndices[globIndex] >= 0)
			index = type->hexVariableIndices[globIndex];

		for(unsigned j = 0; j < hexCount; ++j) {
			int base = j * varCnt;
			if(index != -1) {
				file >> hexVariables[base + index];
				file >> hexBaseVariables[base + index];
			}
			else {
				file.read<float>();
				file.read<float>();
			}
		}
	}
}

void Subsystem::postLoad(Design* design) {
	lookupData.design = design;
	lookupData.system = this;
	lookupData.hexIndex = -1;

	//Initialize hooks
	for(size_t i = 0, cnt = type->hooks.size(); i < cnt; ++i)
		addHook(design, type->hooks[i]);
	for(size_t i = 0, cnt = modules.size(); i < cnt; ++i) {
		auto* module = modules[i];
		if(module) {
			for(size_t n = 0, ncnt = module->hooks.size(); n < ncnt; ++n)
				addHook(design, module->hooks[n]);
		}
	}
}

Subsystem::Subsystem(SaveFile& file)
	: type(nullptr), exteriorHexes(0), hasErrors(false), variables(0), hexVariables(0),
		inDesign(nullptr), index(0), defaults(nullptr), effectors(nullptr)
{
	init(file);
}

void Subsystem::save(SaveFile& file) const {
	file.writeIdentifier(SI_Subsystem, type->index);
	file << core << exteriorHexes << stateOffset << effectorOffset;
	file << direction;
	file << dataOffset;

	file << unsigned(hexes.size());
	file.write(hexes.data(), hexes.size() * sizeof(vec2u));

	for(unsigned i = 0; i < hexes.size(); ++i) {
		file << (unsigned)hexEffects[i].size();
		for(unsigned j = 0; j < hexEffects[i].size(); ++j)
			file << hexEffects[i][j];
	}
	
	file << unsigned(modules.size());
	for(unsigned i = 0; i < modules.size(); ++i)
		file.writeIdentifier(SI_SubsystemModule, modules[i]->umodid);

	file << (unsigned)effects.size();
	for(unsigned i = 0; i < effects.size(); ++i) {
		file.writeIdentifier(SI_Effect, effects[i].type->id);
		file.write(effects[i].values, sizeof(double) * EFFECT_MAX_VALUES);
	}

	for(unsigned i = 0; i < type->effectors.size(); ++i) {
		Effector& effector = effectors[i];
		effector.save(file);
	}

	file.write(defaults, sizeof(BasicType) * type->states.size());

	unsigned cnt = type->variables.size();
	file << cnt;
	for(unsigned i = 0; i < cnt; ++i) {
		file.writeIdentifier(SI_SubsystemVar, type->variables[i].index);
		file << variables[i];
		file << baseVariables[i];
	}

	unsigned varCnt = type->hexVariables.size();
	unsigned hexCnt = hexes.size();
	file << varCnt;
	for(unsigned i = 0; i < varCnt; ++i) {
		file.writeIdentifier(SI_HexVar, type->hexVariables[i].index);
		for(unsigned j = 0; j < hexCnt; ++j) {
			int base = j * varCnt;
			file << hexVariables[base + i];
			file << hexBaseVariables[base + i];
		}
	}
}

void Subsystem::writeData(net::Message& msg) const {
	msg.writeSmall(type->index);

	msg.writeSmall(hexes.size());
	for(size_t i = 0, cnt = hexes.size(); i < cnt; ++i) {
		msg.writeSmall(hexes[i].x);
		msg.writeSmall(hexes[i].y);
		msg.writeSmall(modules[i]->index);
	}

	for(size_t i = 0, cnt = type->modules.size(); i < cnt; ++i)
		msg.writeSmall(moduleCounts[i]);

	msg.writeSmall(core.x);
	msg.writeSmall(core.y);
	msg.writeDirection(direction.x, direction.y, direction.z);
	msg.writeSmall(exteriorHexes);

	msg.writeSmall(stateOffset);
	msg.writeSmall(effectorOffset);

	for(size_t i = 0, cnt = type->variables.size(); i < cnt; ++i) {
		msg << variables[i];
		msg << baseVariables[i];
	}

	unsigned varCnt = type->hexVariables.size() * hexes.size();
	for(size_t i = 0; i < varCnt; ++i) {
		msg << hexVariables[i];
		msg << hexBaseVariables[i];
	}

	for(size_t i = 0; i < type->states.size(); ++i) {
		switch(type->states[i].type) {
			default:
			case BT_Double:
				msg << defaults[i].decimal;
			break;
			case BT_Int:
				msg << defaults[i].integer;
			break;
			case BT_Bool:
				msg << defaults[i].boolean;
			break;
		}
	}

	msg << (unsigned)effects.size();
	for(size_t i = 0, cnt = effects.size(); i < cnt; ++i)
		effects[i].writeData(msg);

	for(size_t i = 0, cnt = type->effectors.size(); i < cnt; ++i)
		effectors[i].writeData(msg);
}

Subsystem::Subsystem(net::Message& msg) : hasErrors(false), inDesign(nullptr), index(0) {
	unsigned sysId = msg.readSmall();
	type = getSubsystemDef(sysId);

	hexes.resize(msg.readSmall());
	modules.resize(hexes.size());
	hexEffects.resize(hexes.size());
	for(size_t i = 0, cnt = hexes.size(); i < cnt; ++i) {
		hexes[i].x = msg.readSmall();
		hexes[i].y = msg.readSmall();
		modules[i] = type->modules[msg.readSmall()];
	}

	moduleCounts.resize(type->modules.size());
	for(size_t i = 0, cnt = type->modules.size(); i < cnt; ++i)
		moduleCounts[i] = msg.readSmall();

	core.x = msg.readSmall();
	core.y = msg.readSmall();
	msg.readDirection(direction.x, direction.y, direction.z);
	exteriorHexes = msg.readSmall();

	stateOffset = msg.readSmall();
	effectorOffset = msg.readSmall();
	dataOffset = 0;

	variables = new float[type->variables.size()];
	baseVariables = new float[type->variables.size()];
	for(size_t i = 0, cnt = type->variables.size(); i < cnt; ++i) {
		msg >> variables[i];
		msg >> baseVariables[i];
	}

	unsigned varCnt = type->hexVariables.size() * hexes.size();
	hexVariables = new float[varCnt];
	hexBaseVariables = new float[varCnt];
	for(size_t i = 0; i < varCnt; ++i) {
		msg >> hexVariables[i];
		msg >> hexBaseVariables[i];
	}

	defaults = new BasicType[type->states.size()];
	for(size_t i = 0; i < type->states.size(); ++i) {
		defaults[i].type = type->states[i].type;
		switch(type->states[i].type) {
			default:
			case BT_Double:
				msg >> defaults[i].decimal;
			break;
			case BT_Int:
				msg >> defaults[i].integer;
			break;
			case BT_Bool:
				msg >> defaults[i].boolean;
			break;
		}
	}

	unsigned cnt = 0;
	msg >> cnt;
	effects.resize(cnt);
	for(size_t i = 0; i < cnt; ++i)
		effects[i].readData(msg);

	effectors = (Effector*)malloc(type->effectors.size() * sizeof(Effector));
	for(size_t i = 0, cnt = type->effectors.size(); i < cnt; ++i)
		new(&effectors[i]) Effector(msg);
}
