import saving;
import hooks;
import util.formatting;
from resources import MoneyType;

#section server
from construction.Constructible import Constructible;
#section all

export ConstructionType, Construction;
export getConstructionTypeCount, getConstructionType;
export Targets, TargetType;

tidy class ConstructionType {
	uint id = 0;
	string ident;
	string name;
	string description;
	string category;
	Sprite icon;
	Targets targets;

	int buildCost = 0;
	int maintainCost = 0;
	double laborCost = 0;
	double timeCost = 0;
	bool alwaysBorrowable = false;
	bool inContext = false;

	array<IConstructionHook@> hooks;

	string formatTooltip(Object& obj) const {
		string tt = format("[font=Medium]$1[/font]\n$2\n", name, description);

		int build = getBuildCost(obj);
		int maint = getMaintainCost(obj);
		if(build != 0 || maint != 0)
			tt += format("[nl/][vspace=6/][img=ResourceIcon::0;22][b][color=#d1cb6a]$1:[/color][/b][offset=120]$2[/offset][/img]",
					locale::COST, formatMoney(build, maint));
		double labor = getLaborCost(obj);
		if(labor != 0)
			tt += format("[nl/][vspace=6/][img=ResourceIcon::6;22][b][color=#b1b4b6]$1:[/color][/b][offset=120]$2[/offset][/img]",
					locale::RESOURCE_LABOR, standardize(labor, true));
		double time = getTimeCost(obj);
		if(time != 0)
			tt += format("[nl/][vspace=6/][img=ContextIcons::1;22][b][color=#b1b4b6]$1:[/color][/b][offset=120]$2[/offset][/img]",
					locale::BUILD_TIME, formatTime(time));

		string vname, vvalue;
		Sprite vicon;
		Color color;
		for(uint i = 0, cnt = hooks.length; i < cnt; ++i) {
			if(hooks[i].getVariable(obj, this, vicon, vname, vvalue, color)) {
				tt += format("[nl/][vspace=6/][img=$1;22][b][color=$4]$2:[/color][/b] [offset=110][hspace=10/]$3[/offset][/img]",
					getSpriteDesc(vicon), vname, vvalue, toString(color));
				color = colors::White;
			}
		}

		return tt;
	}

	string formatCosts(Object& obj, const Targets@ targs = null) const {
		string costs;

		int build = getBuildCost(obj, targs);
		int maint = getMaintainCost(obj, targs);
		if(build != 0 || maint != 0)
			costs += formatMoney(build, maint);
		double labor = getLaborCost(obj, targs);
		if(labor != 0) {
			if(costs.length != 0)
				costs += ", ";
			costs += standardize(labor, true);
			costs += " "+locale::RESOURCE_LABOR;
		}
		string value;
		for(uint i = 0, cnt = hooks.length; i < cnt; ++i) {
			if(hooks[i].formatCost(obj, this, targs, value)) {
				if(costs.length != 0)
					costs += ", ";
				costs += value;
				value = "";
			}
		}
		return costs;
	}

	int getBuildCost(Object& obj, const Targets@ targs = null) const {
		int cost = buildCost;
		for(uint i = 0, cnt = hooks.length; i < cnt; ++i)
			hooks[i].getBuildCost(obj, this, targs, cost);
		return cost;
	}

	int getMaintainCost(Object& obj, const Targets@ targs = null) const {
		int cost = maintainCost;
		for(uint i = 0, cnt = hooks.length; i < cnt; ++i)
			hooks[i].getMaintainCost(obj, this, targs, cost);
		return cost;
	}

	double getLaborCost(Object& obj, const Targets@ targs = null) const {
		double cost = laborCost;
		for(uint i = 0, cnt = hooks.length; i < cnt; ++i)
			hooks[i].getLaborCost(obj, this, targs, cost);
		return cost;
	}

	double getTimeCost(Object& obj, const Targets@ targs = null) const {
		double cost = timeCost;
		return cost;
	}

	bool checkTargets(Object& obj, const Targets@ check) const {
		if(check is null) {
			if(targets.length == 0)
				return true;
			else
				return false;
		}
		if(check.targets.length != targets.length)
			return false;
		for(uint i = 0, cnt = check.targets.length; i < cnt; ++i) {
			if(!isValidTarget(obj, i, check.targets[i]))
				return false;
		}
		return true;
	}

	bool isValidTarget(Object& obj, uint index, const Target@ targ) const {
		if(index >= targets.length)
			return false;
		if(targ.type != targets[index].type)
			return false;
		if(!targ.filled)
			return false;
		if(targets[index].filled && targets[index] != targ)
			return false;
		for(uint i = 0, cnt = hooks.length; i < cnt; ++i) {
			if(!hooks[i].isValidTarget(obj, this, index, targ))
				return false;
		}
		return true;
	}

	bool getTargetError(Object& obj, uint index, const Target@ targ, string& str) const {
		if(index >= targets.length)
			return false;
		if(targ.type != targets[index].type)
			return false;
		if(!targ.filled)
			return false;
		if(targets[index].filled && targets[index] != targ)
			return false;
		for(uint i = 0, cnt = hooks.length; i < cnt; ++i) {
			if(!hooks[i].isValidTarget(obj, this, index, targ)) {
				str = hooks[i].getFailReason(obj, this, index, targ);
				return true;
			}
		}
		return false;
	}

	string getTargetError(Object& obj, const Targets@ check) const {
		string str;
		for(uint i = 0, cnt = check.targets.length; i < cnt; ++i) {
			if(getTargetError(obj, i, check.targets[i], str))
				return str;
		}
		return str;
	}

	bool canBuild(Object& obj, const Targets@ targs = null, bool ignoreCost = false) const {
		if(targs !is null && !checkTargets(obj, targs))
			return false;
		for(uint i = 0, cnt = hooks.length; i < cnt; ++i) {
			if(!hooks[i].canBuild(obj, this, targs, ignoreCost))
				return false;
		}
		if(!ignoreCost && !alwaysBorrowable) {
			int build = getBuildCost(obj, targs);
			if(!obj.owner.canPay(build))
				return false;
		}
		return true;
	}
};

interface IConstructionHook {
#section server
	void start(Construction@ cons, Constructible@ qitem, any@ data) const;
	void cancel(Construction@ cons, Constructible@ qitem, any@ data) const;
	void finish(Construction@ cons, Constructible@ qitem, any@ data) const;
	void tick(Construction@ cons, Constructible@ qitem, any@ data, double time) const;
#section all

	void save(Construction@ cons, any@ data, SaveFile& file) const;
	void load(Construction@ cons, any@ data, SaveFile& file) const;

	string getFailReason(Object& obj, const ConstructionType@ cons, uint index, const Target@ targ) const;
	bool isValidTarget(Object& obj, const ConstructionType@ cons, uint index, const Target@ targ) const;

	bool canBuild(Object& obj, const ConstructionType@ cons, const Targets@ targs, bool ignoreCost) const;

	void getBuildCost(Object& obj, const ConstructionType@ cons, const Targets@ targs, int& cost) const;
	void getMaintainCost(Object& obj, const ConstructionType@ cons, const Targets@ targs, int& cost) const;
	void getLaborCost(Object& obj, const ConstructionType@ cons, const Targets@ targs, double& cost) const;

	bool consume(Construction@ cons, any@ data, const Targets@ targs) const;
	void reverse(Construction@ cons, any@ data, const Targets@ targs, bool cancel = false) const;

	bool getVariable(Object& obj, const ConstructionType@ cons, Sprite& sprt, string& name, string& value, Color& color) const;
	bool formatCost(Object& obj, const ConstructionType@ cons, const Targets@ targs, string& value) const;
	bool getCost(Object& obj, const ConstructionType@ cons, const Targets@ targs, string& value, Sprite& icon) const;
}

class ConstructionHook : Hook, IConstructionHook {
#section server
	void start(Construction@ cons, Constructible@ qitem, any@ data) const {}
	void cancel(Construction@ cons, Constructible@ qitem, any@ data) const {}
	void finish(Construction@ cons, Constructible@ qitem, any@ data) const {}
	void tick(Construction@ cons, Constructible@ qitem, any@ data, double time) const {}
#section all

	void save(Construction@ cons, any@ data, SaveFile& file) const {}
	void load(Construction@ cons, any@ data, SaveFile& file) const {}

	bool consume(Construction@ cons, any@ data, const Targets@ targs) const { return true; }
	void reverse(Construction@ cons, any@ data, const Targets@ targs, bool cancel) const {}

	string getFailReason(Object& obj, const ConstructionType@ cons, uint index, const Target@ targ) const { return ""; }
	bool isValidTarget(Object& obj, const ConstructionType@ cons, uint index, const Target@ targ) const { return true; }

	bool canBuild(Object& obj, const ConstructionType@ cons, const Targets@ targs, bool ignoreCost) const { return true; }

	void getBuildCost(Object& obj, const ConstructionType@ cons, const Targets@ targs, int& cost) const {}
	void getMaintainCost(Object& obj, const ConstructionType@ cons, const Targets@ targs, int& cost) const {}
	void getLaborCost(Object& obj, const ConstructionType@ cons, const Targets@ targs, double& cost) const {}

	bool getVariable(Object& obj, const ConstructionType@ cons, Sprite& sprt, string& name, string& value, Color& color) const { return false; }
	bool formatCost(Object& obj, const ConstructionType@ cons, const Targets@ targs, string& value) const { return false; }
	bool getCost(Object& obj, const ConstructionType@ cons, const Targets@ targs, string& value, Sprite& icon) const { return false; }
};

tidy class Construction : Savable {
	const ConstructionType@ type;
	Object@ obj;
	array<any> data;
	Targets targets;

	Construction() {
	}

	Construction(const ConstructionType@ type) {
		@this.type = type;
		data.length = type.hooks.length;
		targets = Targets(type.targets);
	}

	void save(SaveFile& file) {
		file.writeIdentifier(SI_ConstructionType, type.id);
		file << obj;
		file << targets;
		for(uint i = 0, cnt = type.hooks.length; i < cnt; ++i)
			type.hooks[i].save(this, data[i], file);
	}

	void load(SaveFile& file) {
		uint tid = file.readIdentifier(SI_ConstructionType);
		@type = getConstructionType(tid);
		data.length = type.hooks.length;

		file >> obj;
		file >> targets;

		for(uint i = 0, cnt = type.hooks.length; i < cnt; ++i)
			type.hooks[i].load(this, data[i], file);
	}

#section server
	void start(Constructible@ qitem) {
		for(uint i = 0, cnt = type.hooks.length; i < cnt; ++i)
			type.hooks[i].start(this, qitem, data[i]);
	}

	void cancel(Constructible@ qitem) {
		for(uint i = 0, cnt = type.hooks.length; i < cnt; ++i) {
			type.hooks[i].cancel(this, qitem, data[i]);
			type.hooks[i].reverse(this, data[i], targets, true);
		}

	}

	void finish(Constructible@ qitem) {
		for(uint i = 0, cnt = type.hooks.length; i < cnt; ++i)
			type.hooks[i].finish(this, qitem, data[i]);
		if(qitem.maintainCost != 0)
			obj.owner.modMaintenance(qitem.maintainCost, MoT_Misc);
	}

	void tick(Constructible@ qitem, double time) {
		for(uint i = 0, cnt = type.hooks.length; i < cnt; ++i)
			type.hooks[i].tick(this, qitem, data[i], time);
	}
#section all
};

array<ConstructionType@> constructions;
dictionary constructionIdents;

int getConstructionID(const string& ident) {
	ConstructionType@ type;
	constructionIdents.get(ident, @type);
	if(type !is null)
		return int(type.id);
	return -1;
}

string getConstructionIdent(int id) {
	if(id < 0 || id >= int(constructions.length))
		return "-";
	return constructions[id].ident;
}

string getConstructionName(int id) {
	if(id < 0 || id >= int(constructions.length))
		return "-";
	return constructions[id].name;
}

Sprite getConstructionIcon(int id) {
	if(id < 0 || id >= int(constructions.length))
		return Sprite();
	return constructions[id].icon;
}

uint getConstructionTypeCount() {
	return constructions.length;
}

const ConstructionType@ getConstructionType(uint id) {
	if(id < constructions.length)
		return constructions[id];
	else
		return null;
}

const ConstructionType@ getConstructionType(const string& name) {
	ConstructionType@ cons;
	constructionIdents.get(name, @cons);
	return cons;
}

void addConstructionType(ConstructionType@ cons) {
	cons.id = constructions.length;
	constructions.insertLast(cons);
	constructionIdents.set(cons.ident, @cons);
}

void saveIdentifiers(SaveFile& file) {
	for(uint i = 0, cnt = constructions.length; i < cnt; ++i) {
		ConstructionType@ type = constructions[i];
		file.addIdentifier(SI_ConstructionType, type.id, type.ident);
	}
}

void parseLine(string& line, ConstructionType@ type, ReadFile@ file) {
	//Hook line
	auto@ hook = cast<IConstructionHook>(parseHook(line, "construction_effects::", instantiate=false, file=file));
	if(hook !is null)
		type.hooks.insertLast(hook);
}

void loadConstructions(const string& filename) {
	ReadFile file(filename, true);
	
	string key, value;
	ConstructionType@ type;
	
	uint index = 0;
	while(file++) {
		key = file.key;
		value = file.value;
		
		if(file.fullLine) {
			string line = file.line;
			parseLine(line, type, file);
		}
		else if(key.equals_nocase("Construction")) {
			if(type !is null)
				addConstructionType(type);
			@type = ConstructionType();
			type.ident = value;
		}
		else if(type is null) {
			file.error("Missing Construction ID line");
		}
		else if(key.equals_nocase("Name")) {
			type.name = localize(value);
		}
		else if(key.equals_nocase("Description")) {
			type.description = localize(value);
		}
		else if(key.equals_nocase("Icon")) {
			type.icon = getSprite(value);
		}
		else if(key.equals_nocase("Target")) {
			parseTarget(type.targets, value);
		}
		else if(key.equals_nocase("Build Cost")) {
			type.buildCost = toInt(value);
		}
		else if(key.equals_nocase("Maintenance Cost")) {
			type.maintainCost = toInt(value);
		}
		else if(key.equals_nocase("Labor Cost")) {
			type.laborCost = toDouble(value);
		}
		else if(key.equals_nocase("Time Cost")) {
			type.timeCost = toDouble(value);
		}
		else if(key.equals_nocase("Always Borrowable")) {
			type.alwaysBorrowable = toBool(value);
		}
		else if(key.equals_nocase("Category")) {
			type.category = value;
		}
		else if(key.equals_nocase("In Context")) {
			type.inContext = toBool(value);
		}
		else {
			string line = file.line;
			parseLine(line, type, file);
		}
	}
	
	if(type !is null)
		addConstructionType(type);
}

void preInit() {
	FileList list("data/constructions", "*.txt", true);
	for(uint i = 0, cnt = list.length; i < cnt; ++i)
		loadConstructions(list.path[i]);
}

void init() {
	for(uint i = 0, cnt = constructions.length; i < cnt; ++i) {
		auto@ type = constructions[i];
		for(uint n = 0, ncnt = type.hooks.length; n < ncnt; ++n) {
			if(!cast<Hook>(type.hooks[n]).instantiate())
				error("Could not instantiate hook "+addrstr(type.hooks[n])+" on construction "+type.ident);
			else
				cast<Hook>(type.hooks[n]).initTargets(type.targets);
		}
	}
}
