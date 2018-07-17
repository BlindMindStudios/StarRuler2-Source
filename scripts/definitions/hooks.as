import tile_resources;
import util.formatting;
import int getResourceID(const string&) from "resources";
import string getResourceIdent(int id) from "resources";
import int getAbilityID(const string&) from "abilities";
import string getAbilityIdent(int id) from "abilities";
import int getStatusID(const string&) from "statuses";
import string getStatusIdent(int id) from "statuses";
import int getAttitudeID(const string&) from "attitudes";
import string getAttitudeIdent(int id) from "attitudes";
import int getCargoID(const string&) from "cargo";
import string getCargoIdent(int id) from "cargo";
import int getTraitID(const string&) from "traits";
import string getTraitIdent(int id) from "traits";
import int getRandomEventID(const string&) from "random_events";
import string getRandomEventIdent(int id) from "random_events";
import int getBiomeID(const string&) from "biomes";
import string getBiomeIdent(int id) from "biomes";
import int getOrbitalModuleID(const string&) from "orbitals";
import string getOrbitalModuleIdent(int id) from "orbitals";
import int getConstructionID(const string&) from "constructions";
import string getConstructionIdent(int id) from "constructions";
import int getArtifactID(const string&) from "artifacts";
import string getArtifactIdent(int id) from "artifacts";
import int getBuildingID(const string&) from "buildings";
import string getBuildingIdent(int id) from "buildings";
import int getTechnologyID(const string&) from "research";
import string getTechnologyIdent(int id) from "research";
import int getUnlockTag(const string& ident, bool create = true) from "unlock_tags";
import string getUnlockTagIdent(int id) from "unlock_tags";
import int getObjectStatId(const string& ident, bool create = true) from "object_stats";
import string getObjectStatIdent(int id) from "object_stats";
import string getObjectStatMode(int id) from "object_stats";
import int getObjectStatMode(const string& ident) from "object_stats";
import int getSystemFlag(const string& ident, bool create = true) from "system_flags";
import string getSystemFlagIdent(int id) from "system_flags";
import int getInfluenceCardID(const string& ident) from "influence";
import int getInfluenceVoteID(const string& ident) from "influence";
import int getInfluenceEffectID(const string& ident) from "influence";
import string getInfluenceCardIdent(int id) from "influence";
import string getInfluenceVoteIdent(int id) from "influence";
import string getInfluenceEffectIdent(int id) from "influence";
import hook_globals;
import attributes;
import saving;

export ArgumentType, Argument, REF_ARG;
export Document, EMPTY_DEFAULT;
export Hook, BlockHook, parseHook;
export TargetType, Targets, Target;
export parseTarget;
export makeHookInstance;
export EmpireResource, empResources;

// {{{ Arguments
enum ArgumentType {
	AT_Integer,
	AT_Decimal,
	AT_Boolean,
	AT_TileResource,
	AT_PlanetResource,
	AT_Ability,
	AT_Range,
	AT_Position,
	AT_Position2D,
	AT_Locale,
	AT_PassFail,
	AT_Target,
	AT_TargetSpec,
	AT_EmpAttribute,
	AT_AttributeMode,
	AT_Status,
	AT_Cargo,
	AT_Subsystem,
	AT_Trait,
	AT_OrbitalModule,
	AT_Artifact,
	AT_Technology,
	AT_Global,
	AT_SysVar,
	AT_Sprite,
	AT_Color,
	AT_Hook,
	AT_Model,
	AT_Material,
	AT_Selection,
	AT_PlanetBiome,
	AT_Construction,
	AT_TileResourceSpec,
	AT_Building,
	AT_InfluenceCard,
	AT_InfluenceVote,
	AT_InfluenceEffect,
	AT_CreepCamp,
	AT_RandomEvent,
	AT_Anomaly,
	AT_ObjectType,
	AT_VariableDef,
	AT_ValueDef,
	AT_File,
	AT_UnlockTag,
	AT_ObjectStat,
	AT_ObjectStatMode,
	AT_SystemFlag,
	AT_Custom,
	AT_VarArgs,
	AT_EmpireResource,
	AT_Attitude,
};

enum EmpireResource {
	ER_Money,
	ER_Influence,
	ER_Energy,
	ER_Research,
	ER_Defense,
	ER_FTL,
	ER_COUNT
};

string[] empResources = {
	"Money",
	"Influence",
	"Energy",
	"Research",
	"Defense",
	"FTL"
};

const string EMPTY_DEFAULT = "-";
const string SEP_UNDER = "_";
Argument REF_ARG;
final class Argument {
	ArgumentType type = AT_Custom;
	string argName;
	string str;
	string doc;
	int integer;
	int integer2;
	double decimal;
	double decimal2;
	vec3d position;
	vec3d position2;
	bool boolean;
	bool isRange = false;
	bool filled = false;

	Argument() {
	}

	Argument(ArgumentType Type, const string& def = "", const string& doc = "") {
		type = Type;
		if(def.length != 0) {
			if(def == EMPTY_DEFAULT)
				parse("");
			else
				parse(def);
		}
		if(doc.length != 0)
			this.doc = doc;
	}

	Argument(ArgumentType AType, ArgumentType Type, const string& doc = "", bool required = false) {
		type = AType;
		integer = int(Type);
		boolean = required;
		if(doc.length != 0)
			this.doc = doc;
	}

	Argument(const string& name, ArgumentType Type, const string& defaultValue = "", const string& doc = "") {
		type = Type;
		argName = name;
		boolean = defaultValue.length != 0;
		if(boolean)
			parse(defaultValue);
		if(doc.length != 0)
			this.doc = doc;
	}

	Argument(TargetType Type, const string& def = "", const string& doc = "") {
		type = AT_Target;
		integer2 = int(Type);
		boolean = def.length != 0;
		filled = boolean;
		if(def != EMPTY_DEFAULT)
			str = def;
		if(doc.length != 0)
			this.doc = doc;
	}

	Argument(const string& name, TargetType Type, const string& def = "", const string& doc = "") {
		type = AT_Target;
		argName = name;
		integer2 = int(Type);
		boolean = def.length != 0;
		filled = boolean;
		if(def != EMPTY_DEFAULT)
			str = def;
		if(doc.length != 0)
			this.doc = doc;
	}

	double fromRange() const {
		if(!isRange)
			return decimal;
		return randomd(decimal, decimal2);
	}

	double fromSys(const Subsystem@ sys = null, Object@ efficiencyObj = null) const {
		if(sys is null || integer < 0)
			return decimal;
		double value = decimal;
		if(sys.has(SubsystemVariable(integer)))
			value = sys.variable(SubsystemVariable(integer));
		if(efficiencyObj !is null && efficiencyObj.isShip) {
			Ship@ ship = cast<Ship>(efficiencyObj);
			auto@ status = ship.blueprint.getSysStatus(sys.index);
			if(status !is null)
				value *= double(status.workingHexes) / double(sys.hexCount);
		}
		return value;
	}

	double fromShipEfficiencySum(Object@ efficiencyObj = null) const {
		if(integer < 0)
			return decimal;
		double value = decimal;
		if(efficiencyObj !is null && efficiencyObj.isShip) {
			Ship@ ship = cast<Ship>(efficiencyObj);
			value = ship.blueprint.getEfficiencySum(SubsystemVariable(integer));
		}
		return value;
	}

	void set(double value) {
		decimal = value;
		if(isRange)
			decimal2 = value;
	}

	void set(double value, double value2) {
		decimal = value;
		decimal2 = value2;
	}

	vec3d fromPosition() const {
		if(!isRange)
			return position;
		return vec3d(randomd(position.x, position2.x),
				randomd(position.y, position2.y),
				randomd(position.z, position2.z));
	}

	void set(const vec3d& pos) {
		position = pos;
		if(isRange)
			position2 = pos;
	}

	void set(const vec2d& pos) {
		position = vec3d(pos.x, pos.y, 0);
		if(isRange)
			position2 = position;
	}

	vec2d fromPosition2D() const {
		if(!isRange)
			return vec2d(position.x, position.y);
		return vec2d(randomd(position.x, position2.x),
				randomd(position.y, position2.y));
	}

	Target@ fromTarget(Targets@ targets) const {
		if(uint(integer) >= targets.targets.length)
			return null;
		return targets.targets[integer];
	}

	const Target@ fromConstTarget(const Targets@ targets) const {
		if(uint(integer) >= targets.targets.length)
			return null;
		return targets.targets[integer];
	}

	bool parseRange(double& value, double& value2, const string& str) {
		if(str[0] == '$') {
			value = config::get(str.substr(1));
			value2 = value;
			return false;
		}
		int pos = str.findFirst(":");
		if(pos == -1) {
			value = toDouble(str);
			value2 = value;
			return false;
		}
		else {
			value = toDouble(str.substr(0, pos));
			value2 = toDouble(str.substr(pos+1));
			return true;
		}
	}

	bool instantiate() {
		switch(type) {
			case AT_PlanetResource:
				if(str.length != 0) {
					integer = getResourceID(str);
					if(integer == -1) {
						error(" Error: Unknown planetary resource: "+str);
						return false;
					}
					str = "";
				}
				else {
					integer = -1;
				}
			break;
			case AT_Status:
				if(str.length != 0) {
					integer = getStatusID(str);
					if(integer == -1) {
						error(" Error: Unknown status: "+str);
						return false;
					}
					str = "";
				}
				else {
					integer = -1;
				}
			break;
			case AT_Attitude:
				if(str.length != 0) {
					integer = getAttitudeID(str);
					if(integer == -1) {
						error(" Error: Unknown attitude: "+str);
						return false;
					}
					str = "";
				}
				else {
					integer = -1;
				}
			break;
			case AT_Cargo:
				if(str.length != 0) {
					integer = getCargoID(str);
					if(integer == -1) {
						error(" Error: Unknown cargo: "+str);
						return false;
					}
					str = "";
				}
				else {
					integer = -1;
				}
			break;
			case AT_Trait:
				if(str.length != 0) {
					integer = getTraitID(str);
					if(integer == -1) {
						error(" Error: Unknown trait: "+str);
						return false;
					}
					str = "";
				}
				else {
					integer = -1;
				}
			break;
			case AT_RandomEvent:
				if(str.length != 0) {
					integer = getRandomEventID(str);
					if(integer == -1) {
						error(" Error: Unknown random event: "+str);
						return false;
					}
					str = "";
				}
				else {
					integer = -1;
				}
			break;
			case AT_PlanetBiome:
				if(str.length != 0) {
					integer = getBiomeID(str);
					if(integer == -1) {
						error(" Error: Unknown biome: "+str);
						return false;
					}
				}
				else {
					integer = -1;
				}
			break;
			case AT_Construction:
				if(str.length != 0) {
					integer = getConstructionID(str);
					if(integer == -1) {
						error(" Error: Unknown construction: "+str);
						return false;
					}
				}
				else {
					integer = -1;
				}
			break;
			case AT_Artifact:
				if(str.length != 0) {
					integer = getArtifactID(str);
					if(integer == -1) {
						error(" Error: Unknown artifact: "+str);
						return false;
					}
					str = "";
				}
				else {
					integer = -1;
				}
			break;
			case AT_Building:
				if(str.length != 0) {
					integer = getBuildingID(str);
					if(integer == -1) {
						error(" Error: Unknown building: "+str);
						return false;
					}
					str = "";
				}
				else {
					integer = -1;
				}
			break;
			case AT_Technology:
				if(str.length != 0) {
					integer = getTechnologyID(str);
					if(integer == -1) {
						error(" Error: Unknown technology: "+str);
						return false;
					}
					str = "";
				}
				else {
					integer = -1;
				}
			break;
			case AT_OrbitalModule:
				if(str.length != 0) {
					integer = getOrbitalModuleID(str);
					if(integer == -1) {
						error(" Error: Unknown orbital: "+str);
						return false;
					}
					str = "";
				}
				else {
					integer = -1;
				}
			break;
			case AT_Ability:
				if(str.length != 0) {
					integer = getAbilityID(str);
					if(integer == -1) {
						error(" Error: Unknown ability: "+str);
						return false;
					}
					str = "";
				}
				else {
					integer = -1;
				}
			break;
			case AT_InfluenceCard:
				if(str.length != 0) {
					integer = getInfluenceCardID(str);
					if(integer == -1) {
						error(" Error: Unknown influence card type: "+str);
						return false;
					}
				}
				else {
					integer = -1;
				}
			break;
			case AT_InfluenceVote:
				if(str.length != 0) {
					integer = getInfluenceVoteID(str);
					if(integer == -1) {
						error(" Error: Unknown influence vote type: "+str);
						return false;
					}
				}
				else {
					integer = -1;
				}
			break;
			case AT_InfluenceEffect:
				if(str.length != 0) {
					integer = getInfluenceEffectID(str);
					if(integer == -1) {
						error(" Error: Unknown influence effect type: "+str);
						return false;
					}
				}
				else {
					integer = -1;
				}
			break;
		}
		return true;
	}

	bool parse(const string& value) {
		filled = true;
		str = value;
		switch(type) {
			case AT_Integer:
				integer = toInt(value);
				return true;
			case AT_Boolean:
				if(value[0] == '$')
					boolean = config::get(value.substr(1)) != 0.0;
				else if(value[0] == '!' && value[1] == '$')
					boolean = config::get(value.substr(2)) == 0.0;
				else
					boolean = toBool(value);
				return true;
			case AT_PassFail:
				boolean = value.equals_nocase("pass");
				return true;
			case AT_Decimal:
				if(value[0] == '$')
					decimal = config::get(value.substr(1));
				else
					decimal = toDouble(value);
				return true;
			case AT_Global:
				integer = int(getGlobal(value).id);
				return true;
			case AT_UnlockTag:
				integer = getUnlockTag(value);
				return true;
			case AT_ObjectStat:
				integer = getObjectStatId(value);
				return true;
			case AT_SystemFlag:
				integer = getSystemFlag(value);
				return true;
			case AT_TileResource:
				integer = getTileResource(value);
				if(integer == TR_NULL) {
					error(" Error: Unknown tile resource: "+value);
					return false;
				}
				return true;
			case AT_EmpAttribute:
				if(value.length == 0)
					integer = -1;
				else
					integer = int(getEmpAttribute(value, true));
				str = value;
				return true;
			case AT_AttributeMode:
				integer = int(getAttributeMode(value));
				if(integer == int(AC_INVALID)) {
					error(" Error: Unknown empire attribute mode: "+value);
					return false;
				}
				return true;
			case AT_ObjectStatMode:
				integer = int(getObjectStatMode(value));
				return true;
			case AT_PlanetResource:
				if(value.equals_nocase("null")) {
					integer = -1;
					return true;
				}
				str = value;
				return true;
			case AT_Status:
			case AT_Attitude:
			case AT_Cargo:
			case AT_Trait:
			case AT_RandomEvent:
			case AT_PlanetBiome:
			case AT_Construction:
			case AT_Artifact:
			case AT_Building:
			case AT_Technology:
			case AT_OrbitalModule:
			case AT_Ability:
				str = value;
				return true;
			case AT_Subsystem:
				{
					auto@ def = getSubsystemDef(value);
					if(def is null)
						return false;
					integer = int(def.index);
					return true;
				}
			case AT_Range:
				isRange = parseRange(decimal, decimal2, value);
				return true;
			case AT_Position: {
				string fname;
				array<string> args;
				if(!funcSplit(value, fname, args, true)
					|| args.length != 3 || fname.length != 0) {
					error(" Error: Invalid position spec: "+value);
					return false;
				}
				if(parseRange(position.x, position2.x, args[0]))
					isRange = true;
				if(parseRange(position.y, position2.y, args[1]))
					isRange = true;
				if(parseRange(position.z, position2.z, args[2]))
					isRange = true;
			} return true;
			case AT_Position2D: {
			  string fname;
			  array<string> args;
			  if(!funcSplit(value, fname, args, true)
				  || args.length != 2 || fname.length != 0) {
				  error(" Error: Invalid 2d position spec: "+value);
				  return false;
			  }
			  if(parseRange(position.x, position2.x, args[0]))
				  isRange = true;
			  if(parseRange(position.y, position2.y, args[1]))
				  isRange = true;
			} return true;
			case AT_VarArgs:
				error("Invalid use of variable arguments.");
				return false;
			case AT_Locale:
				str = localize(value);
				return true;
			case AT_Target:
				str = value;
				return true;
			case AT_SysVar: {
				integer = -1;
				decimal = 0;
				string val = value;
				int colon = val.findLast(":");
				if(colon != -1) {
					decimal = toDouble(val.substr(colon+1));
					val = val.substr(0, colon).trimmed();
				}
				if(val.startswith_nocase("sys.")) {
					integer = getSubsystemVariable(val.substr(4));
					if(integer == -1) {
						error("Unknown subsystem variable: "+val);
						return false;
					}
				}
				else if(val[0] == '$')
					decimal = config::get(val.substr(1));
				else
					decimal = toDouble(val);
			} return true;
			case AT_EmpireResource:
				integer = empResources.find(value);
				return integer >= 0;
			case AT_Custom:
			default:
				str = value;
				return true;
		}
		return true;
	}

	string output() const {
		switch(type) {
			case AT_Integer:
				return toString(integer, 0);
			case AT_Global:
				return getGlobal(integer).ident;
			case AT_UnlockTag:
				return getUnlockTagIdent(integer);
			case AT_ObjectStat:
				return getObjectStatIdent(integer);
			case AT_SystemFlag:
				return getSystemFlagIdent(integer);
			case AT_Boolean:
				return boolean ? "True" : "False";
			case AT_PassFail:
				return boolean ? "Pass" : "Fail";
			case AT_Decimal:
				return toString(decimal);
			case AT_SysVar:
				return toString(decimal);
			case AT_TileResource:
				return getTileResourceIdent(integer);
			case AT_PlanetResource:
				return getResourceIdent(integer);
			case AT_Status:
				return getStatusIdent(integer);
			case AT_Attitude:
				return getAttitudeIdent(integer);
			case AT_Cargo:
				return getCargoIdent(integer);
			case AT_Trait:
				return getTraitIdent(integer);
			case AT_RandomEvent:
				return getRandomEventIdent(integer);
			case AT_PlanetBiome:
				return getBiomeIdent(integer);
			case AT_Construction:
				return getConstructionIdent(integer);
			case AT_Artifact:
				return getArtifactIdent(integer);
			case AT_Building:
				return getBuildingIdent(integer);
			case AT_Technology:
				return getTechnologyIdent(integer);
			case AT_OrbitalModule:
				return getOrbitalModuleIdent(integer);
			case AT_Ability:
				return getAbilityIdent(integer);
			case AT_InfluenceCard:
				return getInfluenceCardIdent(integer);
			case AT_InfluenceVote:
				return getInfluenceVoteIdent(integer);
			case AT_InfluenceEffect:
				return getInfluenceEffectIdent(integer);
			case AT_VarArgs:
				return "...";
			case AT_Range:
				if(isRange)
					return toString(decimal)+":"+toString(decimal2);
				else
					return toString(decimal);
			case AT_Position: {
				string output = "(";
				if(position.x == position2.x)
					output += toString(position.x);
				else
					output += toString(position.x)+":"+toString(position2.x);
				output += ", ";
				if(position.y == position2.y)
					output += toString(position.y);
				else
					output += toString(position.y)+":"+toString(position2.y);
				output += ", ";
				if(position.z == position2.z)
					output += toString(position.z);
				else
					output += toString(position.z)+":"+toString(position2.z);
				output += ")";
				return output;
			}
			case AT_Position2D: {
				string output = "(";
				if(position.x == position2.x)
					output += toString(position.x);
				else
					output += toString(position.x)+":"+toString(position2.x);
				output += ", ";
				if(position.y == position2.y)
					output += toString(position.y);
				else
					output += toString(position.y)+":"+toString(position2.y);
				output += ")";
				return output;
			}
			case AT_Target:
				return str;
			case AT_Locale:
				return str;
			case AT_EmpAttribute:
				if(integer == -1)
					return "";
				return getEmpAttributeIdent(integer);
			case AT_AttributeMode:
				return getAttributeModeIdent(integer);
			case AT_ObjectStatMode:
				return getObjectStatMode(integer);
			case AT_EmpireResource:
				if(integer >= 0 && uint(integer) < empResources.length)
					return empResources[integer];
				else
					return empResources[0];
			case AT_Custom:
			default:
				return str;
		}
		return "";
	}
};

final class Document {
	string text;
	bool hidden = false;

	Document(const string& txt) {
		this.text = txt;
	}

	Document(const string& txt, bool hidden) {
		this.text = txt;
		this.hidden = hidden;
	}
};

// }}}
// {{{ Hooks
class Hook {
	array<Argument@> arguments;
	Document@ documentation;
	uint requiredArguments = 0;
	string filePosition;

	//Adding arguments to this hook
	void argument(ArgumentType type) {
		arguments.insertLast(Argument(type));
		++requiredArguments;
	}

	void argument(ArgumentType type, const string& defaultValue) {
		arguments.insertLast(Argument(type, defaultValue, ""));
	}

	void argument(const string& argName, ArgumentType type) {
		arguments.insertLast(Argument(argName, type));
		++requiredArguments;
	}

	void argument(const string& argName, ArgumentType type, const string& defaultValue) {
		arguments.insertLast(Argument(argName, type, defaultValue));
	}

	void varargs(ArgumentType type, bool required = false) {
		Argument arg(AT_VarArgs);
		arg.integer = int(type);
		arg.boolean = required;
		arguments.insertLast(arg);
		if(required)
			++requiredArguments;
	}

	void target(const string& argName, TargetType type) {
		Argument arg(AT_Target);
		arg.integer2 = int(type);
		arg.boolean = false;
		arguments.insertLast(arg);
		++requiredArguments;
	}

	void target(const string& argName, TargetType type, const string& defaultValue) {
		Argument arg(AT_Target);
		arg.integer2 = int(type);
		arg.boolean = true;
		arg.str = defaultValue;
		arguments.insertLast(arg);
	}

	string formatHook() {
		string txt;
		txt = getClass(this).name;
		txt += "(";
		for(uint i = 0, cnt = arguments.length; i < cnt; ++i) {
			if(i != 0)
				txt += ", ";
			txt += arguments[i].output();
		}
		txt += ")";
		return txt;
	}

	string formatDeclaration() {
		string txt;
		txt = getClass(this).name;
		txt += "(";
		for(uint i = 0, cnt = arguments.length; i < cnt; ++i) {
			if(i != 0)
				txt += ", ";
			auto@ arg = arguments[i];
			txt += "<"+arg.argName+">";
			if(arg.filled && arg.type != AT_Hook)
				txt += " = "+arg.output();
		}
		txt += ")";
		return txt;
	}

	//Parse arguments from strings
#section server
	bool init(Design& design, Subsystem& subsystem, StringList& arglist, DoubleList& values) const {
		array<string> args;
		for(uint i = 0, cnt = arglist.length; i < cnt; ++i)
			args.insertLast(arglist[i]);
		initClass();
		if(!parse("--", args)) {
			printError("Error in hook "+formatHook());
			return false;
		}
		for(uint i = 0, cnt = min(values.length, arguments.length); i < cnt; ++i) {
			switch(arguments[i].type) {
				case AT_Decimal: arguments[i].decimal = values[i]; break;
				case AT_Integer: arguments[i].integer = values[i]; break;
				case AT_Range: arguments[i].decimal = values[i]; arguments[i].decimal2 = values[i]; break;
			}
		}
		if(!instantiate()) {
			printError("Error in hook "+formatHook());
			return false;
		}
		return true;
	}
#section all

	void printError(const string& message) {
		if(filePosition.length != 0)
			error(filePosition);
		error(message);
	}

	bool parse(const string& name, array<string>& args) {
		if(args.length < requiredArguments) {
			printError(" Error: mismatched argument count, expected "+arguments.length+" arguments.");
			return false;
		}
		bool inNamed = false;
		uint i = 0;
		for(uint cnt = arguments.length, acnt = args.length; i < cnt && i < acnt; ++i) {
			int eqPos = args[i].findFirst("=");
			int brkPos = args[i].findFirst("(");
			if(eqPos != -1 && (brkPos == -1 || eqPos < brkPos)) {
				//Named argument
				uint index = uint(-1);
				inNamed = true;
				string name = args[i].substr(0, eqPos).trimmed();
				string value = args[i].substr(eqPos+1).trimmed();
				for(uint n = 0; n < cnt; ++n) {
					if(arguments[n].argName.equals_nocase(name)) {
						index = n;
						break;
					}
				}

				if(index == uint(-1)) {
					printError(" Error: Could not find argument with name: "+name);
					return false;
				}
				else {
					if(!arguments[index].parse(value))
						return false;
				}
			}
			else {
				//Positional argument
				if(inNamed) {
					printError(" Error: positional arguments cannot follow named ones.");
					return false;
				}
				//Variable arguments
				if(arguments[i].type == AT_VarArgs) {
					auto varType = ArgumentType(arguments[i].integer);
					arguments.removeAt(i);
					for(uint n = i; n < acnt; ++n) {
						Argument arg(varType);
						if(!arg.parse(args[n]))
							return false;
						arguments.insertLast(arg);
					}
				}
				//Normal arguments
				else if(!arguments[i].parse(args[i])) {
					printError("Error in arguments.");
					return false;
				}
			}
		}
		if(i < requiredArguments) {
			if(arguments[i].type != AT_VarArgs || arguments[i].boolean) {
				printError(" Error: mismatched argument count, expected "+arguments.length+" arguments.");
				return false;
			}
		}
		for(uint i = 0, cnt = requiredArguments; i < cnt; ++i) {
			if(!arguments[i].filled) {
				printError(" Error: no value for argument "+i+" ("+arguments[i].argName+")");
				return false;
			}
		}
		return true;
	}

	//Pluck arguments from class
	void initClass() {
		auto@ argClass = getClass(REF_ARG);
		auto@ thisClass = getClass(this);
		for(uint i = 0, cnt = thisClass.memberCount; i < cnt; ++i) {
			auto@ ptr = thisClass.getMember(this, i);
			auto@ mem = cast<Argument>(ptr);
			if(mem is null) {
				if(cast<Document>(ptr) !is null)
					@documentation = cast<Document>(ptr);
				continue;
			}
			if(mem.argName.length == 0) {
				mem.argName = thisClass.memberName[i];
				if(mem.argName.findFirst(SEP_UNDER) != -1) {
					array<string>@ splt = mem.argName.split(SEP_UNDER);
					mem.argName = "";
					for(uint i = 0, cnt = splt.length; i < cnt; ++i) {
						splt[i][0] = uppercase(splt[i][0]);
						if(i != 0)
							mem.argName += " ";
						mem.argName += splt[i];
					}
				}
				else {
					mem.argName[0] = uppercase(mem.argName[0]);
				}
			}
			arguments.insertLast(mem);
			if(mem.type == AT_VarArgs) {
				if(mem.boolean)
					++requiredArguments;
			}
			else if(!mem.filled) {
				++requiredArguments;
			}
		}
	}

	//Called when the hook is first created in its type
	bool instantiate() {
		for(uint i = 0, cnt = arguments.length; i < cnt; ++i)
			if(!arguments[i].instantiate())
				return false;
		return true;
	}

	//Figure out target arguments
	bool initTargets(Targets@ targets) {
		uint targCnt = targets.targets.length;
		for(uint i = 0, cnt = arguments.length; i < cnt; ++i) {
			auto@ arg = arguments[i];
			if(arg.type != AT_Target)
				continue;

			//Find the target index
			uint index = uint(-1);
			for(uint n = 0; n < targCnt; ++n) {
				if(targets.targets[n].name.equals_nocase(arg.str)) {
					index = n;
					break;
				}
			}

			if(index >= targets.targets.length) {
				if(arg.boolean) {
					arg.integer = -1;
					continue;
				}
				printError("Could not find target: "+arg.str);
				return false;
			}

			//Check for type
			auto@ targ = targets.targets[index];
			if(arg.integer2 != int(TT_Any)) {
				if(targ.type != TargetType(arg.integer2)) {
					printError("Target "+targ.name+" is not of appropriate type.");
					return false;
				}
			}
			else {
				arg.integer2 = int(targ.type);
			}

			//Record index
			arg.integer = int(index);
		}
		return true;
	}
};

class BlockHook : Hook {
	int indent = 0;
	array<Hook@> inner;

	BlockHook@ getInside(int indent, const string& line) {
		if(inner.length > 0) {
			BlockHook@ block = cast<BlockHook@>(inner[inner.length - 1]);
			if(block !is null) {
				@block = block.getInside(indent, line);
				if(block !is null)
					return block;
			}
		}
		if(indent > this.indent)
			return this;
		return null;
	}

	void addHook(Hook@ hook) {
		inner.insertLast(hook);
	}

	bool prepare(Argument@& arg) const {
		return true;
	}

	bool feed(Argument@& arg, Hook@& hook, uint& num) const {
		if(num >= inner.length)
			return false;

		@hook = inner[num];
		num += 1;
		return true;
	}
};
// }}}
// {{{ Targets
enum TargetType {
	TT_Empire,
	TT_Object,
	TT_Side,
	TT_Card,
	TT_Vote,
	TT_Effect,
	TT_String,
	TT_Point,
	TT_ID,
	TT_Any,
	TT_Custom,
	
	TT_COUNT
};

TargetType getTargetType(const string& str) {
	if(str.equals_nocase("empire"))
		return TT_Empire;
	if(str.equals_nocase("object"))
		return TT_Object;
	if(str.equals_nocase("side"))
		return TT_Side;
	if(str.equals_nocase("card"))
		return TT_Card;
	if(str.equals_nocase("vote"))
		return TT_Vote;
	if(str.equals_nocase("id"))
		return TT_ID;
	if(str.equals_nocase("effect"))
		return TT_Effect;
	if(str.equals_nocase("text"))
		return TT_String;
	if(str.equals_nocase("point"))
		return TT_Point;
	return TT_Custom;
}

const array<string> TARGET_TYPE_NAMES = {
	"Empire", "Object", "Side", "Card", "Vote",
	"Effect", "Text", "Point", "ID", "Any", "Custom"};

final class Target : Serializable, Savable {
	TargetType type = TT_Custom;
	bool filled = false;
	string name;

	Empire@ emp;
	Object@ obj;
	string str;
	bool side;
	int id;
	vec3d point;

	Target() {
	}

	Target(TargetType Type) {
		type = Type;
	}

	string format(bool pretty = true) const {
		if(!filled)
			return locale::CARD_GENERIC;
		switch(type) {
			case TT_Empire:
				if(emp !is null && playerEmpire !is null && playerEmpire.valid && playerEmpire.ContactMask & emp.mask == 0)
					return "???";
				if(pretty)
					return formatEmpireName(emp);
				else if(emp is null)
					return locale::CARD_GENERIC;
				else
					return emp.name;
			case TT_Object:
				if(pretty)
					return formatObject(obj);
				else if(obj is null)
					return locale::CARD_GENERIC;
				else
					return obj.name;
			case TT_Side: return side ? locale::SUPPORT : locale::OPPOSE;
			case TT_String: case TT_Custom: return str;
			case TT_Point: return ""+point;
		}
		return "...";
	}

	bool opEquals(const Target& other) const {
		if(type != other.type)
			return false;
		if(filled != other.filled)
			return false;
		if(filled) {
			switch(type) {
				case TT_Empire: return emp is other.emp;
				case TT_Object: return obj is other.obj;
				case TT_Side: return side == other.side;
				case TT_String: case TT_Custom: return str == other.str;
				case TT_Vote: case TT_Card: case TT_Effect: case TT_ID:
					return id == other.id;
				case TT_Point: return point == other.point;
			}
			return false;
		}
		else {
			return true;
		}
	}

	//Networking
	void writeData(Message& msg, TargetType Type) {
		msg << filled;
		if(filled) {
			switch(Type) {
				case TT_Empire: msg << emp; break;
				case TT_Object: msg << obj; break;
				case TT_Side: msg << side; break;
				case TT_Point: msg << point; break;
				case TT_String: case TT_Custom: msg << str; break;
				case TT_Vote: case TT_Card: case TT_Effect: case TT_ID:
					msg << id; break;
			}
		}
	}

	void write(Message& msg) {
		uint Type = type;
		msg.writeLimited(type, TT_COUNT-1);
		msg << name;
		writeData(msg, type);
	}

	void readData(Message& msg, TargetType Type) {
		msg >> filled;
		if(filled) {
			switch(Type) {
				case TT_Empire: msg >> emp; break;
				case TT_Object: msg >> obj; break;
				case TT_Side: msg >> side;break;
				case TT_Point: msg >> point; break;
				case TT_String: case TT_Custom: msg >> str; break;
				case TT_Vote: case TT_Card: case TT_Effect: case TT_ID:
					msg >> id; break;
			}
		}
	}

	void read(Message& msg) {
		type = TargetType(msg.readLimited(TT_COUNT-1));
		msg >> name;
		readData(msg, type);
	}

	//Saving
	void saveData(SaveFile& file, TargetType Type) {
		file << filled;
		switch(Type) {
			case TT_Empire: file << emp; break;
			case TT_Object: file << obj; break;
			case TT_Side: file << side; break;
    		case TT_Point: file << point; break;
			case TT_String: case TT_Custom: file << str; break;
			case TT_Vote: case TT_Card: case TT_Effect: case TT_ID:
				file << id; break;
		}
	}

	void save(SaveFile& file) {
		uint Type = type;
		file << Type;
		file << name;
		saveData(file, type);
	}

	void loadData(SaveFile& file, TargetType Type) {
		file >> filled;
		switch(Type) {
			case TT_Empire: file >> emp; break;
			case TT_Object: file >> obj; break;
			case TT_Side: file >> side; break;
			case TT_Point: file >> point; break;
			case TT_String: case TT_Custom: file >> str; break;
			case TT_Vote: case TT_Card: case TT_Effect: case TT_ID:
				file >> id; break;
		}
	}

	void load(SaveFile& file) {
		uint Type = 0;
		file >> Type;
		type = TargetType(Type);
		file >> name;
		loadData(file, type);
	}
};

final class Targets : Serializable, Savable {
	array<Target> targets;

	//Empty list of targets
	Targets() {
	}

	//Add a new target
	Target@ add(const string& name, TargetType type) {
		targets.length = targets.length+1;
		Target@ targ = targets[targets.length-1];
		targ.type = type;
		targ.name = name;
		return targ;
	}

	Target@ add(TargetType type, bool fill = false) {
		targets.length = targets.length+1;
		Target@ targ = targets[targets.length-1];
		targ.type = type;
		targ.filled = fill;
		return targ;
	}

	//Copy existing targets
	Targets(const Targets@ other) {
		targets = other.targets;
	}

	void set(const Targets@ other) {
		targets = other.targets;
	}

	//Get a target variable
	Target@ get(const string& name) {
		for(uint i = 0, cnt = targets.length; i < cnt; ++i) {
			if(targets[i].name == name)
				return targets[i];
		}
		return null;
	}

	Target@ fill(const string& name) {
		auto@ targ = get(name);
		if(targ !is null)
			targ.filled = true;
		return targ;
	}

	Target@ fill(uint index) {
		auto@ targ = targets[index];
		if(targ !is null)
			targ.filled = true;
		return targ;
	}

	int getIndex(const string& name) {
		for(uint i = 0, cnt = targets.length; i < cnt; ++i) {
			if(targets[i].name == name)
				return int(i);
		}
		return -1;
	}

	string format(const string& text, bool pretty = true) const {
		array<string> args;
		formatInto(args, pretty);
		return ::format(text, args);
	}

	void formatInto(array<string>& args, bool pretty = true) const {
		for(uint i = 0, cnt = targets.length; i < cnt; ++i)
			args.insertLast(targets[i].format(pretty));
	}

	string format(bool pretty = true) const {
		string targs = "";
		for(uint i = 0, cnt = targets.length; i < cnt; ++i) {
			if(i != 0)
				targs += ", ";
			targs += targets[i].format(pretty);
		}
		return targs;
	}

	//Check equality of target values
	bool opEquals(const Targets& other) const {
		if(other.targets.length != targets.length)
			return false;
		for(uint i = 0, cnt = targets.length; i < cnt; ++i) {
			if(targets[i] != other.targets[i])
				return false;
		}
		return true;
	}

	//Quick access
	const Target@ opIndex(uint index) const {
		if(index >= targets.length)
			return null;
		return targets[index];
	}

	Target@ opIndex(uint index) {
		if(index >= targets.length)
			return null;
		return targets[index];
	}

	Target@ opIndex(const string& name) {
		return get(name);
	}

	const Target@ opIndex(const string& name) const {
		return get(name);
	}

	uint get_length() const {
		return targets.length;
	}

	//Networking
	Targets(Message& msg) {
		read(msg);
	}

	Targets(Message& msg, const Targets@ def) {
		readData(msg, def);
	}

	void write(Message& msg) {
		uint cnt = targets.length;
		msg.writeSmall(cnt);
		for(uint i = 0; i < cnt; ++i)
			msg << targets[i];
	}

	void read(Message& msg) {
		uint cnt = msg.readSmall();
		targets.length = cnt;
		for(uint i = 0; i < cnt; ++i)
			msg >> targets[i];
	}

	void writeData(Message& msg, const Targets@ def) {
		for(uint i = 0, cnt = def.targets.length; i < cnt; ++i)
			targets[i].writeData(msg, def.targets[i].type);
	}

	void readData(Message& msg, const Targets@ def) {
		set(def);
		for(uint i = 0, cnt = def.targets.length; i < cnt; ++i)
			targets[i].readData(msg, def.targets[i].type);
	}

	//Saving
	Targets(SaveFile& file) {
		load(file);
	}

	Targets(SaveFile& file, const Targets@ def) {
		loadData(file, def);
	}

	void save(SaveFile& file) {
		uint cnt = targets.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i)
			file << targets[i];
	}

	void load(SaveFile& file) {
		uint cnt = 0;
		file >> cnt;
		targets.length = cnt;
		for(uint i = 0; i < cnt; ++i)
			file >> targets[i];
	}

	void saveData(SaveFile& file, const Targets@ def) {
		for(uint i = 0, cnt = def.targets.length; i < cnt; ++i)
			targets[i].saveData(file, def.targets[i].type);
	}

	void loadData(SaveFile& file, const Targets@ def) {
		set(def);
		for(uint i = 0, cnt = def.targets.length; i < cnt; ++i)
			targets[i].loadData(file, def.targets[i].type);
	}
};
//}}}
//{{{ Parser
Hook@ parseHook(array<Hook@>& list, int indent, const string& line, const string& defaultNamespace) {
	BlockHook@ inBlock;
	if(list.length != 0) {
		@inBlock = cast<BlockHook>(list[list.length-1]);
		if(inBlock !is null)
			@inBlock = inBlock.getInside(indent, line);
	}

	Hook@ hook = parseHook(line, defaultNamespace);
	BlockHook@ newBlock = cast<BlockHook>(hook);
	if(newBlock !is null)
		newBlock.indent = indent;

	if(hook !is null) {
		if(inBlock !is null)
			inBlock.addHook(hook);
		else
			list.insertLast(hook);
	}
	return hook;
}

void error(ReadFile@ file, const string& message) {
	if(file !is null)
		file.error(message);
	else
		error(message);
}

Hook@ parseHook(const string& line, const string& defaultNamespace, bool required = true, bool instantiate = true, ReadFile@ file = null) {
	array<string> args;
	string name;

	//Deal with version handling
	string parseLine = line;
	int lastBrkt = line.findLast(")");
	int hashPos = line.findLast("#");
	if(hashPos != -1 && hashPos > lastBrkt) {
		int ltPos = line.findLast("#version<");
		if(ltPos != -1) {
			if(line.length <= uint(ltPos+9) || line[ltPos+9] == '=') {
				error(file, "ERROR: Unknown hook tag: "+parseLine.substr(hashPos));
			}
			else {
				int cmpVersion = toInt(line.substr(ltPos+9))-1;
				if(isLoadedSave) {
					if(START_VERSION >= cmpVersion)
						return null;
				}
				else {
					if(SV_CURRENT >= cmpVersion)
						return null;
				}
				parseLine = parseLine.substr(0, hashPos);
			}
		}
		else {
			int gtePos = line.findLast("#version>=");
			if(gtePos != -1) {
				int cmpVersion = toInt(line.substr(gtePos+10))-1;
				if(isLoadedSave && START_VERSION < cmpVersion)
					return null;
				parseLine = parseLine.substr(0, hashPos);
			}
			else {
				error(file, "ERROR: Unknown hook tag: "+parseLine.substr(hashPos));
			}
		}
	}

	//Parse the actual hook
	if(!funcSplit(parseLine, name, args)) {
		error(file, "Invalid hook: "+escape(parseLine.trimmed()));
		return null;
	}

	bool hasNamespace = true;
	if(name.findFirst("::") == -1) {
		name = defaultNamespace + name;
		hasNamespace = false;
	}
	AnyClass@ cls = getClass(name.trimmed());
	if(!hasNamespace)
		name = name.substr(defaultNamespace.length);
	if(cls is null) {
		if(required && (!hasNamespace || (isServer && !isShadow)) && !isScriptDebug)
			error(file, "Could not find hook class: "+escape(name.trimmed())+" in "+escape(line.trimmed()));
		return null;
	}

	Hook@ hook = cast<Hook>(cls.create());
	if(hook is null) {
		if(required && (!hasNamespace || (isServer && !isShadow)) && !isScriptDebug)
			error(file, "Could not find hook class: "+escape(name.trimmed())+" in "+escape(line.trimmed()));
		return null;
	}
	hook.initClass();
	if(!hook.parse(name, args)) {
		error(file, "Invalid arguments to hook: "+escape(line.trimmed()));
		return null;
	}
	if(instantiate && !hook.instantiate()) {
		error(file, "Could not instantiate hook: "+escape(line.trimmed()));
		return null;
	}

	if(file !is null)
		hook.filePosition = file.position();
	return hook;
}

Hook@ makeHookInstance(const string& line, const string& defaultNamespace, const string& enforceType = "") {
	string name;

	int pos = line.findFirst("(");
	if(pos == -1)
		name = line;
	else
		name = line.substr(0, pos);

	if(name.findFirst("::") == -1)
		name = defaultNamespace + name;

	AnyClass@ cls = getClass(name.trimmed());
	if(cls is null)
		return null;

	if(enforceType.length != 0) {
		AnyClass@ checkType = getClass(enforceType);
		if(checkType !is null && !cls.implements(checkType))
			return null;
	}

	Hook@ hook = cast<Hook>(cls.create());
	if(hook is null)
		return null;

	hook.initClass();
	return hook;
}

Target@ parseTarget(Targets@ targets, const string& line, bool allowCustom = false) {
	int pos = line.findFirst("=");
	if(pos == -1) {
		error("Invalid target spec: "+escape(line));
		return null;
	}

	string name = line.substr(0, pos).trimmed();
	string type = line.substr(pos+1).trimmed();
	
	TargetType tt = getTargetType(type);
	if(!allowCustom && tt == TT_Custom) {
		error("Invalid target type: "+escape(type));
		return null;
	}

	return targets.add(name, tt);
}
//}}}
