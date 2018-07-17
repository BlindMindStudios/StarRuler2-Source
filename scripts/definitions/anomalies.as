#priority init 2000
import hooks;
import saving;

export AnomalyType, AnomalyOption, AnomalyState;
export getAnomalyType, getAnomalyTypeCount;
export getDistributedAnomalyType;
export Targets;

tidy final class AnomalyOption {
	uint id = 0;
	Sprite icon;
	string ident, desc;
	string blurb;
	bool isSafe = true;
	double chance = 1.0;

	array<IAnomalyHook@> hooks;

	array<AnomalyResult@> results;
	double resultTotal = 0.0;

	Targets targets;

	bool checkTargets(Empire@ emp, const Targets@ check) const {
		if(check is null) {
			if(targets.targets.length == 0)
				return true;
			else
				return false;
		}
		if(check.targets.length != targets.targets.length)
			return false;
		for(uint i = 0, cnt = check.targets.length; i < cnt; ++i) {
			if(!isValidTarget(emp, i, check.targets[i]))
				return false;
		}
		return true;
	}

	bool isValidTarget(Empire@ emp, uint index, const Target@ targ) const {
		if(index >= targets.targets.length)
			return false;
		if(targ.type != targets.targets[index].type)
			return false;
		if(!targ.filled)
			return false;
		if(targets.targets[index].filled && targets.targets[index] != targ)
			return false;
		for(uint i = 0, cnt = hooks.length; i < cnt; ++i) {
			if(!hooks[i].isValidTarget(emp, index, targ))
				return false;
		}
		return true;
	}
	
#section server
	void choose(Anomaly@ anomaly, Empire@ emp, Targets@ targets) const {
		if(!checkTargets(emp, targets))
			return;

		for(uint i = 0, cnt = hooks.length; i < cnt; ++i)
			hooks[i].choose(anomaly, emp, targets);

		double roll = randomd(0.0, resultTotal);
		for(uint i = 0, cnt = results.length; i < cnt; ++i) {
			if(roll <= results[i].chance) {
				results[i].choose(anomaly, emp, targets);
				break;
			}
			roll -= results[i].chance;
		}
	}

	bool giveOption(Anomaly@ anomaly, Empire@ emp) const {
		for(uint i = 0, cnt = hooks.length; i < cnt; ++i) {
			if(!hooks[i].giveOption(anomaly, emp))
				return false;
		}
		return true;
	}
#section all
};

tidy class AnomalyResult {
	double chance = 1.0;
	array<IAnomalyHook@> hooks;

	void choose(Anomaly@ anomaly, Empire@ emp, Targets@ targets) const {
		for(uint i = 0, cnt = hooks.length; i < cnt; ++i)
			hooks[i].choose(anomaly, emp, targets);
	}
};

interface IAnomalyHook {
	void init(AnomalyType@ type);
	void choose(Anomaly@ obj, Empire@ emp, Targets@ targets) const;
	bool giveOption(Anomaly@ obj, Empire@ emp) const;
	bool isValidTarget(Empire@ emp, uint index, const Target@ targ) const;
};

tidy class AnomalyHook : Hook, IAnomalyHook {
	void init(AnomalyType@ type) {}
	void choose(Anomaly@ obj, Empire@ emp, Targets@ targets) const {}
	bool giveOption(Anomaly@ obj, Empire@ emp) const { return true; }
	bool isValidTarget(Empire@ emp, uint index, const Target@ targ) const { return true; }
};

tidy class AnomalyType {
	uint id = 0;
	string ident, name = locale::ANOMALY, desc, narrative;
	string modelName = "Debris", matName = "Asteroid";

	double frequency = 1.0;
	double scanTime = 60.0;
	bool unique = false;
	
	double stateTotal = 0.0;
	array<AnomalyState@> states;
	array<AnomalyOption@> options;

	const AnomalyState@ getState() const {
		if(states.length == 0)
			return null;
		double value = randomd(0.0, stateTotal);
		for(uint i = 0, cnt = states.length; i < cnt; ++i) {
			if(value <= states[i].frequency)
				return states[i];
			value -= states[i].frequency;
		}
		return states[states.length-1];
	}

	const AnomalyOption@ getOption(const string& ident) const {
		for(uint i = 0, cnt = options.length; i < cnt; ++i) {
			if(options[i].ident == ident)
				return options[i];
		}
		return null;
	}

	const AnomalyState@ getState(const string& ident) const {
		for(uint i = 0, cnt = states.length; i < cnt; ++i) {
			if(states[i].ident == ident)
				return states[i];
		}
		return null;
	}
};

tidy class AnomalyState {
	uint id = 0;
	string ident;
	string narrative;
	string modelName = "Debris", matName = "Asteroid";
	array<const AnomalyOption@> options;
	array<double> option_chances;
	array<string> def_options;
	double frequency = 1.0;
};

void parseLine(string& line, AnomalyType@ anomaly, AnomalyResult@ result, ReadFile@ file) {
	//Try to find the design
	if(line.findFirst("(") == -1) {
		error("Invalid line during " + anomaly.ident+": "+escape(line));
	}
	else {
		if(anomaly.options.length == 0) {
			error("Missing 'Pickup:' line for: "+escape(line));
			return;
		}

		//Hook line
		auto@ hook = cast<IAnomalyHook>(parseHook(line, "anomaly_effects::", instantiate=false, file=file));
		if(hook !is null) {
			if(result !is null)
				result.hooks.insertLast(hook);
			else
				anomaly.options[anomaly.options.length-1].hooks.insertLast(hook);
		}
	}
}

void loadAnomaly(const string& filename) {
	ReadFile file(filename, true);
	
	string key, value;
	AnomalyType@ anomaly;
	AnomalyOption@ opt;
	AnomalyState@ state;
	AnomalyResult@ result;
	
	uint index = 0;
	while(file++) {
		key = file.key;
		value = file.value;
		
		if(file.fullLine) {
			if(anomaly is null) {
				error("Missing 'Anomaly: ID' line in " + filename);
				continue;
			}
			if(opt is null) {
				error("Missing 'Option: ID' line in " + filename);
				continue;
			}

			string line = file.line;
			parseLine(line, anomaly, result, file);
		}
		else if(key == "Anomaly") {
			if(anomaly !is null)
				addAnomalyType(anomaly);
			@state = null;
			@opt = null;
			@result = null;
			@anomaly = AnomalyType();
			anomaly.ident = value;
			if(anomaly.ident.length == 0)
				anomaly.ident = filename+"__"+index;

			@opt = null;
			++index;
		}
		else if(anomaly is null) {
			error("Missing 'Anomaly: ID' line in " + filename);
		}
		else if(key == "Name") {
			anomaly.name = localize(value);
		}
		else if(key == "Scan Time") {
			anomaly.scanTime = toDouble(value);
		}
		else if(key == "Unique") {
			anomaly.unique = toBool(value);
		}
		else if(key == "Model") {
			if(state !is null)
				state.modelName = value;
			else
				anomaly.modelName = value;
		}
		else if(key == "Material") {
			if(state !is null)
				state.matName = value;
			else
				anomaly.matName = value;
		}
		else if(key == "Description") {
			if(anomaly.desc.length == 0)
				anomaly.desc = localize(value);
			else if(opt !is null)
				opt.desc = localize(value);
			else
				error("Duplicate Description for " + anomaly.ident + ". Missing Option line?");
		}
		else if(key == "Blurb") {
			if(opt !is null)
				opt.blurb = localize(value);
		}
		else if(key == "Narrative") {
			if(state !is null)
				state.narrative = localize(value);
			else
				anomaly.narrative = localize(value);
		}
		else if(key == "Frequency") {
			if(state !is null)
				state.frequency = toDouble(value);
			else
				anomaly.frequency = toDouble(value);
		}
		else if(key == "Icon") {
			if(opt !is null)
				opt.icon = getSprite(value);
			else
				file.error("Icon outside option block.");
		}
		else if(key == "Option") {
			@state = null;
			@result = null;
			@opt = AnomalyOption();
			opt.id = anomaly.options.length;
			opt.ident = value;
			if(opt.ident.length == 0)
				opt.ident = anomaly.ident+"__opt__"+anomaly.options.length;
			
			anomaly.options.insertLast(opt);
		}
		else if(key == "Safe") {
			if(opt !is null)
				opt.isSafe = toBool(value);
		}
		else if(key == "State") {
			@opt = null;
			@result = null;
			@state = AnomalyState();
			state.id = anomaly.states.length;
			state.ident = value;
			state.modelName = anomaly.modelName;
			state.matName = anomaly.matName;
			if(state.ident.length == 0)
				state.ident = anomaly.ident+"__state__"+anomaly.states.length;
			anomaly.states.insertLast(state);
		}
		else if(key == "Result") {
			if(opt is null) {
				file.error("Result outside option block.");
				continue;
			}
			@state = null;
			@result = AnomalyResult();
			if(value.length == 0)
				result.chance = 1.0;
			else
				result.chance = toDouble(value);
			
			opt.resultTotal += result.chance;
			opt.results.insertLast(result);
		}
		else if(key == "Chance") {
			if(opt is null) {
				file.error("Chance outside option block.");
				continue;
			}
			double chance = 0.0;
			if(value.findFirst("%") == -1)
				chance = toDouble(value);
			else
				chance = toDouble(value) / 100.0;
			opt.chance = chance;
		}
		else if(key == "Choice") {
			if(state is null) {
				file.error("Choice outside state block.");
				continue;
			}

			int pos = value.findFirst("=");
			if(pos == -1) {
				state.def_options.insertLast(value);
				state.option_chances.insertLast(1.0);
			}
			else {
				state.def_options.insertLast(value.substr(0, pos).trimmed());
				state.option_chances.insertLast(toDouble(value.substr(pos+1)) / 100.0);
			}
		}
		else if(file.key == "Target") {
			if(opt is null) {
				file.error("Target outside option block.");
				continue;
			}
			parseTarget(opt.targets, file.value);
		}
		else {
			string line = file.line;
			parseLine(line, anomaly, result, file);
		}
	}
	
	if(anomaly !is null)
		addAnomalyType(anomaly);
}

void preInit() {
	//Load anomaly types
	FileList list("data/anomalies", "*.txt", true);
	for(uint i = 0, cnt = list.length; i < cnt; ++i)
		loadAnomaly(list.path[i]);
}

void init() {
	auto@ list = anomalyTypes;
	for(uint i = 0, cnt = list.length; i < cnt; ++i) {
		auto@ type = list[i];
		type.stateTotal = 0;
		for(uint o = 0, ocnt = type.options.length; o < ocnt; ++o) {
			auto@ opt = type.options[o];
			for(uint n = 0, ncnt = opt.hooks.length; n < ncnt; ++n) {
				if(!cast<Hook>(opt.hooks[n]).instantiate())
					error("Could not instantiate hook: "+addrstr(opt.hooks[n])+" in "+type.ident);
				cast<Hook>(opt.hooks[n]).initTargets(opt.targets);
				opt.hooks[n].init(type);
			}
			for(uint n = 0, ncnt = opt.results.length; n < ncnt; ++n) {
				auto@ res = opt.results[n];
				for(uint j = 0, jcnt = res.hooks.length; j < jcnt; ++j) {
					if(!cast<Hook>(res.hooks[j]).instantiate())
						error("Could not instantiate hook: "+addrstr(res.hooks[j])+" in "+type.ident);
					cast<Hook>(res.hooks[j]).initTargets(opt.targets);
					res.hooks[j].init(type);
				}
			}
		}
		for(uint o = 0, ocnt = type.states.length; o < ocnt; ++o) {
			auto@ state = type.states[o];
			type.stateTotal += state.frequency;
			for(uint n = 0, ncnt = state.def_options.length; n < ncnt; ++n) {
				auto@ opt = type.getOption(state.def_options[n]);
				if(opt !is null)
					state.options.insertLast(opt);
				else
					error("Could not find option: "+state.def_options[n]);
			}
		}
	}
}

AnomalyType@[] anomalyTypes;
dictionary idents;
double totalFrequency = 0;

const AnomalyType@ getAnomalyType(uint id) {
	if(id >= anomalyTypes.length)
		return null;
	return anomalyTypes[id];
}

const AnomalyType@ getAnomalyType(const string& ident) {
	AnomalyType@ anomaly;
	if(idents.get(ident, @anomaly))
		return anomaly;
	return null;
}

uint getAnomalyTypeCount() {
	return anomalyTypes.length;
}

const AnomalyType@ getDistributedAnomalyType() {
	uint count = anomalyTypes.length;

	double num = randomd(0, totalFrequency);
	for(uint i = 0, cnt = anomalyTypes.length; i < cnt; ++i) {
		AnomalyType@ type = anomalyTypes[i];
		double freq = type.frequency;
		if(num <= freq) {
			if(type.unique) {
				totalFrequency -= type.frequency;
				type.frequency = 0;
			}
			return type;
		}
		num -= freq;
	}
	return anomalyTypes[anomalyTypes.length-1];
}

void addAnomalyType(AnomalyType@ type) {
	type.id = anomalyTypes.length;
	anomalyTypes.insertLast(type);
	idents.set(type.ident, @type);
	totalFrequency += type.frequency;
}

void saveIdentifiers(SaveFile& file) {
	for(uint i = 0, cnt = anomalyTypes.length; i < cnt; ++i) {
		auto type = anomalyTypes[i];
		file.addIdentifier(SI_AnomalyType, type.id, type.ident);
	}
}
