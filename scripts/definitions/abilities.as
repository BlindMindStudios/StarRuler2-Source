import saving;
import hooks;
import icons;
import util.formatting;

export AbilityType, Ability;
export getAbilityTypeCount, getAbilityType;
export Targets, TargetType;

tidy final class AbilityType {
	uint id = 0;
	string ident;
	string name;
	string description;
	double energyCost = 0.0;
	double cooldown = 0.0;
	double range = INFINITY;
	Sprite icon = icons::Ability;
	Targets targets;
	int objectCast = -1;
	int hotkey = 0;
	bool empireDefault = false;
	bool hideGlobal = false;
	const SoundSource@ activateSound;

	array<IAbilityHook@> hooks;
};

interface IAbilityHook {
	void create(Ability@ abl, any@ data) const;
	void destroy(Ability@ abl, any@ data) const;
	void enable(Ability@ abl, any@ data) const;
	void disable(Ability@ abl, any@ data) const;
	void tick(Ability@ abl, any@ data, double time) const;
	void save(Ability@ abl, any@ data, SaveFile& file) const;
	void load(Ability@ abl, any@ data, SaveFile& file) const;
	void changeTarget(Ability@ abl, any@ data, uint index, Target@ oldTarget, Target@ newTarget) const;

	void modEnergyCost(const Ability@ abl, const Targets@ targs, double& cost) const;

	string getFailReason(const Ability@ abl, uint index, const Target@ targ) const;
	bool isValidTarget(const Ability@ abl, uint index, const Target@ targ) const;

	bool canActivate(const Ability@ abl, const Targets@ targs, bool ignoreCost) const;
	void activate(Ability@ abl, any@ data, const Targets@ targs) const;

	bool consume(Ability@ abl, any@ data, const Targets@ targs) const;
	void reverse(Ability@ abl, any@ data, const Targets@ targs) const;

	bool getVariable(const Ability@ abl, Sprite& sprt, string& name, string& value, Color& color) const;
	bool formatCost(const Ability@ abl, const Targets@ targs, string& value) const;

	bool isChanneling(const Ability@ abl, const any@ data) const;
}

class AbilityHook : Hook, IAbilityHook {
	void create(Ability@ abl, any@ data) const {}
	void destroy(Ability@ abl, any@ data) const {}
	void enable(Ability@ abl, any@ data) const {}
	void disable(Ability@ abl, any@ data) const {}
	void tick(Ability@ abl, any@ data, double time) const {}
	void save(Ability@ abl, any@ data, SaveFile& file) const {}
	void load(Ability@ abl, any@ data, SaveFile& file) const {}

	void changeTarget(Ability@ abl, any@ data, uint index, Target@ oldTarget, Target@ newTarget) const {}
	string getFailReason(const Ability@ abl, uint index, const Target@ targ) const { return ""; }
	bool isValidTarget(const Ability@ abl, uint index, const Target@ targ) const { return true; }

	void modEnergyCost(const Ability@ abl, const Targets@ targs, double& cost) const {}

	bool canActivate(const Ability@ abl, const Targets@ targs, bool ignoreCost) const { return true; }
	void activate(Ability@ abl, any@ data, const Targets@ targs) const {}

	bool consume(Ability@ abl, any@ data, const Targets@ targs) const { return true; }
	void reverse(Ability@ abl, any@ data, const Targets@ targs) const {}

	bool getVariable(const Ability@ abl, Sprite& sprt, string& name, string& value, Color& color) const { return false; }
	bool formatCost(const Ability@ abl, const Targets@ targs, string& value) const { return false; }

	bool isChanneling(const Ability@ abl, const any@ data) const { return false; }
};

tidy class Ability : Serializable, Savable {
	int id = -1;
	const AbilityType@ type;
	const Subsystem@ subsystem;
	Empire@ emp;
	Object@ obj;
	Object@ toggle;
	bool disabled = false;
	double cooldown = 0.0;
	array<any> data;
	Targets targets;

	Ability() {
	}

	Ability(const AbilityType@ type) {
		@this.type = type;
		data.length = type.hooks.length;
		targets = Targets(type.targets);
	}

	double getRange(const Targets@ targs = null) const {
		return type.range;
	}

	bool isChanneling() const {
		for(uint i = 0, cnt = type.hooks.length; i < cnt; ++i) {
			if(type.hooks[i].isChanneling(this, data[i]))
				return true;
		}
		return false;
	}

	string formatTooltip(Empire@ forEmp = null) const {
		string tt;
		tt += format("[b]$1[/b]", type.name);
		if(type.hotkey != 0)
			tt += format(" "+locale::ABL_HOTKEY_SPEC, getKeyDisplayName(type.hotkey));
		tt += "\n"+type.description+"\n";

		string vname, vvalue;
		Sprite vicon;
		Color color;
		for(uint i = 0, cnt = type.hooks.length; i < cnt; ++i) {
			if(type.hooks[i].getVariable(this, vicon, vname, vvalue, color)) {
				tt += format("[nl/][vspace=6/][img=$1;22][b][color=$4]$2[/color][/b] [offset=120]$3[/offset][/img]",
					getSpriteDesc(vicon), vname, vvalue, toString(color));
				color = colors::White;
			}
		}

		double cost = getEnergyCost();
		if(cost != 0)
			tt += format("[nl/][vspace=6/][img=ResourceIcon::2;22][b][color=#20b6e3]$1:[/color][/b][offset=120]$2[/offset][/img]",
					locale::ENERGY_COST, standardize(cost, true));
		if(type.cooldown != 0) {
			if(cooldown > 0) {
				tt += format("[nl/][vspace=6/][img=ContextIcons::1;22][b][color=#9622bb]$1:[/color][/b][offset=120]$2 / $3[/offset][/img]",
						locale::COOLDOWN, formatTime(cooldown), formatTime(type.cooldown));
			}
			else {
				tt += format("[nl/][vspace=6/][img=ContextIcons::1;22][b][color=#9622bb]$1:[/color][/b][offset=120]$2[/offset][/img]",
						locale::COOLDOWN, formatTime(type.cooldown));
			}
		}
		else if(cooldown > 0) {
			tt += format("[nl/][vspace=6/][img=ContextIcons::1;22][b][color=#9622bb]$1:[/color][/b][offset=120]$2[/offset][/img]",
					locale::COOLDOWN, formatTime(cooldown));
		}
		return tt;
	}

	string formatCosts(const Targets@ targs = null) const {
		string costs;
		double cost = getEnergyCost(targs);
		if(cost > 0)
			costs += format(locale::ABILITY_ENERGY, standardize(cost));
		string value;
		for(uint i = 0, cnt = type.hooks.length; i < cnt; ++i) {
			if(type.hooks[i].formatCost(this, targs, value)) {
				if(costs.length != 0)
					costs += ", ";
				costs += value;
				value = "";
			}
		}
		return costs;
	}

	void changeTarget(const Argument@ arg, Target@ newTarg) {
		Target@ storeTarg = arg.fromTarget(targets);
		for(uint i = 0, cnt = type.hooks.length; i < cnt; ++i)
			type.hooks[i].changeTarget(this, data[i], arg.integer, storeTarg, newTarg);
		storeTarg = newTarg;
	}

	void write(Message& msg) {
		msg << type.id;
		msg << id;
		msg << disabled;
		msg << cooldown;
		msg << emp;
		msg << obj;
		msg << targets;
		if(subsystem !is null) {
			msg.write1();
			msg << subsystem.inDesign;
			msg << subsystem.index;
		}
		else {
			msg.write0();
		}
	}

	void read(Message& msg) {
		uint tid = 0;
		msg >> tid;
		@type = getAbilityType(tid);
		msg >> id;
		msg >> disabled;
		msg >> cooldown;
		msg >> emp;
		msg >> obj;
		msg >> targets;
		if(msg.readBit()) {
			const Design@ dsg;
			msg >> dsg;
			@subsystem = dsg.subsystems[msg.read_uint()];
		}
	}

	void save(SaveFile& file) {
		file << id;
		file.writeIdentifier(SI_AbilityType, type.id);
		file << disabled;
		file << cooldown;
		file << emp;
		file << obj;
		file << targets;
		if(subsystem !is null) {
			file.write1();
			file << subsystem.inDesign;
			file << subsystem.index;
		}
		else {
			file.write0();
		}
		for(uint i = 0, cnt = type.hooks.length; i < cnt; ++i)
			type.hooks[i].save(this, data[i], file);
	}

	void load(SaveFile& file) {
		file >> id;

		uint tid = file.readIdentifier(SI_AbilityType);
		@type = getAbilityType(tid);
		data.length = type.hooks.length;

		file >> disabled;
		file >> cooldown;
		file >> emp;
		file >> obj;
		if(file >= SV_0081)
			file >> targets;
		else
			targets = Targets(type.targets);
		if(file.readBit()) {
			const Design@ dsg;
			file >> dsg;
			uint index = 0;
			file >> index;
			@subsystem = dsg.subsystems[index];
		}
		for(uint i = 0, cnt = type.hooks.length; i < cnt; ++i)
			type.hooks[i].load(this, data[i], file);
	}

	double getEnergyCost(const Targets@ targs = null) const {
		double cost = type.energyCost;
		for(uint i = 0, cnt = type.hooks.length; i < cnt; ++i)
			type.hooks[i].modEnergyCost(this, targs, cost);
		return cost;
	}

	bool checkTargets(const Targets@ check) const {
		if(check is null) {
			if(type.targets.length == 0)
				return true;
			else
				return false;
		}
		if(check.targets.length != type.targets.length)
			return false;
		for(uint i = 0, cnt = check.targets.length; i < cnt; ++i) {
			if(!isValidTarget(i, check.targets[i]))
				return false;
		}
		return true;
	}

	bool isValidTarget(uint index, const Target@ targ) const {
		if(index >= type.targets.length)
			return false;
		if(targ.type != type.targets[index].type)
			return false;
		if(!targ.filled)
			return false;
		if(type.targets[index].filled && type.targets[index] != targ)
			return false;
		for(uint i = 0, cnt = type.hooks.length; i < cnt; ++i) {
			if(!type.hooks[i].isValidTarget(this, index, targ))
				return false;
		}
		return true;
	}

	bool canActivate(const Targets@ targs = null, bool ignoreCost = false) const {
		if(targs !is null && !checkTargets(targs))
			return false;
		for(uint i = 0, cnt = type.hooks.length; i < cnt; ++i) {
			if(!type.hooks[i].canActivate(this, targs, ignoreCost))
				return false;
		}
		if(!ignoreCost) {
			double energy = getEnergyCost(targs);
			if(energy != 0.0 && emp.EnergyStored < energy)
				return false;
		}
		return true;
	}

	bool getTargetError(uint index, const Target@ targ, string& str) const {
		if(index >= type.targets.length)
			return false;
		if(targ.type != type.targets[index].type)
			return false;
		if(!targ.filled)
			return false;
		if(type.targets[index].filled && type.targets[index] != targ)
			return false;
		for(uint i = 0, cnt = type.hooks.length; i < cnt; ++i) {
			if(!type.hooks[i].isValidTarget(this, index, targ)) {
				str = type.hooks[i].getFailReason(this, index, targ);
				return true;
			}
		}
		return false;
	}

	string getTargetError(const Targets@ check) {
		string str;
		for(uint i = 0, cnt = check.targets.length; i < cnt; ++i) {
			if(getTargetError(i, check.targets[i], str))
				return str;
		}
		return str;
	}

#section server
	bool activate(const Targets@ targs) {
		if(!canActivate(targs))
			return false;
		double energy = getEnergyCost(targs);
		if(energy != 0.0 && emp.consumeEnergy(energy, false) == 0.0)
			return false;
		for(uint i = 0, cnt = type.hooks.length; i < cnt; ++i) {
			if(!type.hooks[i].consume(this, data[i], targs)) {
				for(uint j = 0; j < i; ++j)
					type.hooks[j].reverse(this, data[j], targs);
				if(energy != 0.0)
					emp.modEnergyStored(energy);
				return false;
			}
		}
		cooldown = -1.0;
		for(uint i = 0, cnt = type.hooks.length; i < cnt; ++i)
			type.hooks[i].activate(this, data[i], targs);
		if(cooldown < 0) {
			if(type.cooldown != 0.0)
				cooldown = type.cooldown;
			else
				cooldown = 0;
		}
		return true;
	}

	void create() {
		for(uint i = 0, cnt = type.hooks.length; i < cnt; ++i)
			type.hooks[i].create(this, data[i]);
	}

	void destroy() {
		for(uint i = 0, cnt = type.hooks.length; i < cnt; ++i)
			type.hooks[i].destroy(this, data[i]);
	}

	void enable() {
		for(uint i = 0, cnt = type.hooks.length; i < cnt; ++i)
			type.hooks[i].enable(this, data[i]);
	}

	void disable() {
		for(uint i = 0, cnt = type.hooks.length; i < cnt; ++i)
			type.hooks[i].disable(this, data[i]);
	}

	void tick(double time) {
		for(uint i = 0, cnt = type.hooks.length; i < cnt; ++i)
			type.hooks[i].tick(this, data[i], time);
	}
#section all
};

array<AbilityType@> abilities;
dictionary abilityIdents;

int getAbilityID(const string& ident) {
	AbilityType@ type;
	abilityIdents.get(ident, @type);
	if(type !is null)
		return int(type.id);
	return -1;
}

string getAbilityIdent(int id) {
	if(id < 0 || id >= int(abilities.length))
		return "-";
	return abilities[id].ident;
}

uint getAbilityTypeCount() {
	return abilities.length;
}

const AbilityType@ getAbilityType(uint id) {
	if(id < abilities.length)
		return abilities[id];
	else
		return null;
}

const AbilityType@ getAbilityType(const string& name) {
	AbilityType@ abl;
	abilityIdents.get(name, @abl);
	return abl;
}

void addAbilityType(AbilityType@ abl) {
	abl.id = abilities.length;
	abilities.insertLast(abl);
	abilityIdents.set(abl.ident, @abl);
}

void saveIdentifiers(SaveFile& file) {
	for(uint i = 0, cnt = abilities.length; i < cnt; ++i) {
		AbilityType@ type = abilities[i];
		file.addIdentifier(SI_AbilityType, type.id, type.ident);
	}
}

void parseLine(string& line, AbilityType@ type, ReadFile@ file) {
	//Hook line
	auto@ hook = cast<IAbilityHook>(parseHook(line, "ability_effects::", instantiate=false, file=file));
	if(hook !is null)
		type.hooks.insertLast(hook);
}

void loadAbilities(const string& filename) {
	ReadFile file(filename, true);
	
	string key, value;
	AbilityType@ type;
	
	uint index = 0;
	while(file++) {
		key = file.key;
		value = file.value;
		
		if(file.fullLine) {
			string line = file.line;
			parseLine(line, type, file);
		}
		else if(key.equals_nocase("Ability")) {
			if(type !is null)
				addAbilityType(type);
			@type = AbilityType();
			type.ident = value;
		}
		else if(type is null) {
			file.error("Missing Ability ID line");
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
		else if(key.equals_nocase("Energy Cost")) {
			type.energyCost = toDouble(value);
		}
		else if(key.equals_nocase("Cooldown")) {
			type.cooldown = toDouble(value);
		}
		else if(key.equals_nocase("Range")) {
			type.range = toDouble(value);
		}
		else if(key.equals_nocase("Hide Global")) {
			type.hideGlobal = toBool(value);
		}
		else if(key.equals_nocase("Empire Default")) {
			type.empireDefault = toBool(value);
		}
		else if(key.equals_nocase("Target")) {
			parseTarget(type.targets, value);
		}
		else if(key.equals_nocase("Activate Sound")) {
			@type.activateSound = getSound(value);
			if(type.activateSound is null)
				file.error("Could not find activation sound '"+value+"'.");
		}
		else if(key.equals_nocase("Hotkey")) {
			type.hotkey = getKey(value);
		}
		else if(key.equals_nocase("Object Cast")) {
			auto@ targ = type.targets.get(value);
			if(targ is null) {
				file.error("Could not find target "+value);
				continue;
			}
			if(targ.type != TT_Object) {
				file.error("Target "+value+" is not an object target.");
				continue;
			}

			type.objectCast = type.targets.getIndex(value);
		}
		else {
			string line = file.line;
			parseLine(line, type, file);
		}
	}
	
	if(type !is null)
		addAbilityType(type);
}

void preInit() {
	FileList list("data/abilities", "*.txt", true);
	for(uint i = 0, cnt = list.length; i < cnt; ++i)
		loadAbilities(list.path[i]);
}

void init() {
	for(uint i = 0, cnt = abilities.length; i < cnt; ++i) {
		auto@ type = abilities[i];
		for(uint n = 0, ncnt = type.hooks.length; n < ncnt; ++n) {
			if(!cast<Hook>(type.hooks[n]).instantiate())
				error("Could not instantiate hook "+addrstr(type.hooks[n])+" on ability "+type.ident);
			else
				cast<Hook>(type.hooks[n]).initTargets(type.targets);
		}
	}
}
