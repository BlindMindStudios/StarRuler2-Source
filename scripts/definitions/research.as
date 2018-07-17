#priority init 2000
import hooks;
import saving;
import attributes;

export TechnologyType, TechnologyNode, TechnologyClass;
export TechAddModifier, parseModifier;

export getTechnology, getTechnologyCount;
export getTechnologyID, getTechnologyIdent;

export TechnologyGridSpec, getTechnologyGridSpec;
export TechnologyGrid;

//{{{ Technologies
interface ITechnologyHook {
	void unlock(TechnologyNode@ node, Empire& emp) const;
	bool canUnlock(TechnologyNode@ node, Empire& emp) const;
	bool canBeSecret(TechnologyNode@ node, Empire& emp) const;
	bool getSecondaryUnlock(TechnologyNode@ node, Empire@ emp, string& text) const;
	bool canSecondaryUnlock(TechnologyNode@ node, Empire& emp) const;
	bool consumeSecondary(TechnologyNode@ node, Empire& emp) const;
	void reverseSecondary(TechnologyNode@ node, Empire& emp) const;
	void tick(TechnologyNode@ node, Empire& emp, double time) const;
	void onStateChange(TechnologyNode@ node, Empire@ emp) const;
	void addToDescription(TechnologyNode@ node, Empire@ emp, string& description) const;
	void modPointCost(const TechnologyNode@ node, Empire& emp, double& pointCost) const;
	void modTimeCost(const TechnologyNode@ node, Empire& emp, double& timeCost) const;
};

class TechnologyHook : ITechnologyHook, Hook {
	void unlock(TechnologyNode@ node, Empire& emp) const {}
	bool canUnlock(TechnologyNode@ node, Empire& emp) const { return true; }
	bool canBeSecret(TechnologyNode@ node, Empire& emp) const { return true; }
	bool getSecondaryUnlock(TechnologyNode@ node, Empire@ emp, string& text) const { return false; }
	bool canSecondaryUnlock(TechnologyNode@ node, Empire& emp) const { return true; }
	bool consumeSecondary(TechnologyNode@ node, Empire& emp) const { return true; }
	void reverseSecondary(TechnologyNode@ node, Empire& emp) const {}
	void tick(TechnologyNode@ node, Empire& emp, double time) const {}
	void onStateChange(TechnologyNode@ node, Empire@ emp) const {}
	void addToDescription(TechnologyNode@ node, Empire@ emp, string& description) const {}
	void modPointCost(const TechnologyNode@ node, Empire& emp, double& pointCost) const {}
	void modTimeCost(const TechnologyNode@ node, Empire& emp, double& timeCost) const {}
};

enum TechnologyClass {
	Tech_Boost,
	Tech_Upgrade,
	Tech_BigUpgrade,
	Tech_Unlock,
	Tech_Keystone,
	Tech_Secret,
	Tech_Special,
};

tidy final class TechnologyType {
	uint id;
	string ident;
	string name;
	string description;
	string blurb;
	string secondaryTerm = locale::RESEARCH_STUDY;
	Sprite icon;
	Sprite symbol;
	Color color;
	uint cls = Tech_Upgrade;

	string dlc;
	string dlcReplace;
	string category = "Vanilla";
	
	bool secret = false;
	double secretFrequency = 1.0;
	bool defaultUnlock = false;
	double pointCost = 0;
	double timeCost = 0;

	array<ITechnologyHook@> hooks;
};

tidy final class TechnologyNode : Serializable, Savable {
	int id = -1;
	vec2i position;
	const TechnologyType@ type;

	//Whether the node has completely finished unlocking
	bool unlocked = false;

	//Whether the node has been purchased in some way, and will unlock in time
	bool bought = false;

	//Whether this node can be bought (has bought nodes adjacent)
	bool available = false;

	//Whether this node can start unlocking (has unlocked nodes adjacent)
	bool unlockable = false;

	//Whether this node was unlocked using its secondary option
	bool secondaryUnlock = false;

	//Whether this node has been queued to be researched
	bool queued = false;

	//Whether this is a secret node
	bool secret = false;
	bool secretPicked = false;

	//Unlock time remaining
	double timer = -1.0;

	void write(Message& msg) {
		msg.writeSignedSmall(id);
		msg.writeSignedSmall(position.x);
		msg.writeSignedSmall(position.y);
		msg.writeSmall(type.id);
		msg << unlocked << bought;
		msg << available << unlockable << queued;
		msg << secret << secretPicked;
		msg << float(timer);
	}

	void read(Message& msg) {
		id = msg.readSignedSmall();
		position.x = msg.readSignedSmall();
		position.y = msg.readSignedSmall();
		@type = getTechnology(msg.readSmall());
		msg >> unlocked >> bought;
		msg >> available >> unlockable >> queued;
		msg >> secret >> secretPicked;
		timer = msg.read_float();
	}

	void writeStatus(Message& msg) {
		msg << unlocked << bought;
		msg << available << unlockable << queued;
		msg << secret << secretPicked;
		if(timer >= 0) {
			msg.write1();
			msg << float(timer);
		}
		else {
			msg.write0();
		}
	}

	void readStatus(Message& msg) {
		msg >> unlocked >> bought;
		msg >> available >> unlockable >> queued;
		msg >> secret >> secretPicked;
		if(msg.readBit())
			timer = msg.read_float();
		else
			timer = -1.0;
	}

	void save(SaveFile& file) {
		file << id;
		file.writeIdentifier(SI_Technology, type.id);
		file << position;
		file << unlocked << bought;
		file << available << unlockable;
		file << secondaryUnlock;
		file << timer;
		file << queued;
		file << secret << secretPicked;
	}

	void load(SaveFile& file) {
		file >> id;
		@type = getTechnology(file.readIdentifier(SI_Technology));
		file >> position;
		file >> unlocked >> bought;
		file >> available >> unlockable;
		file >> secondaryUnlock;
		file >> timer;
		if(file >= SV_0135)
			file >> queued;
		if(file >= SV_0137)
			file >> secret >> secretPicked;
	}

	double getPointCost(Empire@ emp = null) const {
		double pointCost = type.pointCost;
		if(emp !is null) {
			for(uint i = 0, cnt = type.hooks.length; i < cnt; ++i)
				type.hooks[i].modPointCost(this, emp, pointCost);
		}
		if(emp !is null)
			pointCost *= emp.ResearchCostFactor;
		return pointCost;
	}

	double getTimeCost(Empire@ emp = null) const {
		double timeCost = type.timeCost;
		if(emp !is null) {
			for(uint i = 0, cnt = type.hooks.length; i < cnt; ++i)
				type.hooks[i].modTimeCost(this, emp, timeCost);
		}
		return timeCost;
	}

	bool hasSecondary(Empire@ emp = null) {
		string tmp;
		for(uint i = 0, cnt = type.hooks.length; i < cnt; ++i)
			if(type.hooks[i].getSecondaryUnlock(this, emp, tmp))
				return true;
		return false;
	}

	bool canSecondaryUnlock(Empire& emp) {
		if(!hasSecondary(emp))
			return false;
		if(secret && !secretPicked)
			return false;
		for(uint i = 0, cnt = type.hooks.length; i < cnt; ++i)
			if(!type.hooks[i].canSecondaryUnlock(this, emp))
				return false;
		return true;
	}

	bool canUnlock(Empire& emp) {
		if(!available)
			return false;
		if(secret && !secretPicked)
			return false;
		for(uint i = 0, cnt = type.hooks.length; i < cnt; ++i)
			if(!type.hooks[i].canUnlock(this, emp))
				return false;
		return true;
	}

	bool hasRequirements(Empire& emp) {
		for(uint i = 0, cnt = type.hooks.length; i < cnt; ++i)
			if(!type.hooks[i].canUnlock(this, emp))
				return false;
		return true;
	}

	bool canBeSecret(Empire& emp) {
		for(uint i = 0, cnt = type.hooks.length; i < cnt; ++i)
			if(!type.hooks[i].canBeSecret(this, emp))
				return false;
		return true;
	}

	string getSecondaryCost(Empire@ emp = null, const string& sep = locale::RESEARCH_COST_JOIN) {
		string text, elem;
		for(uint i = 0, cnt = type.hooks.length; i < cnt; ++i) {
			if(type.hooks[i].getSecondaryUnlock(this, emp, elem)) {
				if(text.length != 0)
					text += sep;
				text += elem;
				elem = "";
			}
		}
		return text;
	}

	bool consumeSecondary(Empire& emp) {
		for(uint i = 0, cnt = type.hooks.length; i < cnt; ++i) {
			if(!type.hooks[i].consumeSecondary(this, emp)) {
				for(uint n = 0; n < i; ++n)
					type.hooks[n].reverseSecondary(this, emp);
				return false;
			}
		}
		return true;
	}

#section server
	void buy(Empire& emp) {
		timer = getTimeCost(emp);
		bought = true;
		queued = false;
	}

	void tick(Empire& emp, TechnologyGrid& grid, double time) {
		if(available && queued && !bought) {
			double cost = getPointCost(emp);
			if(cost > 0) {
				if(emp.ResearchPoints >= type.pointCost && canUnlock(emp))
					emp.research(id);
			}
			else {
				if(canUnlock(emp))
					emp.research(id, secondary=true);
			}
			return;
		}
		if(timer >= 0 && unlockable) {
			timer -= time * emp.ResearchUnlockSpeed;
			if(timer <= 0) {
				timer = -1.0;
				grid.markUnlocked(position, emp);
				unlock(emp);
			}
		}
		for(uint i = 0, cnt = type.hooks.length; i < cnt; ++i)
			type.hooks[i].tick(this, emp, time);
	}

	void unlock(Empire& emp) {
		unlocked = true;
		for(uint i = 0, cnt = type.hooks.length; i < cnt; ++i)
			type.hooks[i].unlock(this, emp);
		if(type.cls == Tech_Unlock)
			emp.modAttribute(EA_ResearchUnlocksDone, AC_Add, 1.0);
	}
#section all

	void stateChange(Empire@ emp) {
		for(uint i = 0, cnt = type.hooks.length; i < cnt; ++i)
			type.hooks[i].onStateChange(this, emp);
	}

	int opCmp(const TechnologyNode& other) const {
		if(other.timer < timer)
			return 1;
		if(timer < other.timer)
			return -1;
		return 0;
	}
};

tidy final class TechnologyGrid : Savable {
	HexGridi indices;
	vec2i minPos;
	vec2i maxPos;
	array<TechnologyNode@> nodes;

	void save(SaveFile& file) {
		file << minPos;
		file << maxPos;

		uint cnt = nodes.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i)
			file << nodes[i];
	}

	void load(SaveFile& file) {
		file >> minPos;
		file >> maxPos;

		uint cnt = 0;
		file >> cnt;
		nodes.length = cnt;
		for(uint i = 0; i < cnt; ++i) {
			TechnologyNode node;
			file >> node;
			@nodes[i] = node;
		}
		regenGrid();
	}

	void regenBounds() {
		minPos = vec2i(INT_MAX, INT_MAX);
		maxPos = vec2i(INT_MIN, INT_MIN);

		for(uint i = 0, cnt = nodes.length; i < cnt; ++i) {
			auto@ node = nodes[i];
			minPos.x = min(minPos.x, node.position.x);
			minPos.y = min(minPos.y, node.position.y);
			maxPos.x = max(maxPos.x, node.position.x);
			maxPos.y = max(maxPos.y, node.position.y);
		}

		if(minPos.y % 2 != 0)
			minPos.y -= 1;
		regenGrid();
	}

	void insert(const vec2i& pos, TechnologyNode@ node) {
		nodes.insertLast(node);
		regenBounds();
	}

	void remove(const vec2i& pos) {
		auto@ node = getNode(pos);
		if(node !is null) {
			nodes.remove(node);
			regenBounds();
		}
	}

	void regenGrid() {
		indices.resize(maxPos.x - minPos.x + 1, maxPos.y - minPos.y + 1);
		indices.clear(-1);
		for(uint i = 0, cnt = nodes.length; i < cnt; ++i) {
			vec2u relPos = vec2u(nodes[i].position - minPos);
			if(!indices.valid(relPos))
				continue;
			indices[relPos] = int(i);
		}
	}

	TechnologyNode@ getNode(const vec2i& pos) {
		vec2u relPos = vec2u(pos - minPos);
		if(!indices.valid(relPos))
			return null;
		int ind = indices[relPos];
		if(ind == -1 || ind >= int(nodes.length))
			return null;
		return nodes[ind];
	}

	int getIndex(const vec2i& pos) {
		vec2u relPos = vec2u(pos - minPos);
		if(!indices.valid(relPos))
			return -1;
		int ind = indices[relPos];
		if(ind == -1 || ind >= int(nodes.length))
			return -1;
		return ind;
	}

	TechnologyNode@ getAdjacentNode(const vec2i& pos, uint adj) {
		vec2i adv = pos;
		if(!doAdvance(adv, HexGridAdjacency(adj)))
			return null;
		return getNode(adv);
	}

	bool doAdvance(vec2i& pos, HexGridAdjacency adj) {
		vec2u flipped(pos.y-minPos.y, pos.x-minPos.x);
		if(!advanceHexPosition(flipped, vec2u(maxPos.y-minPos.y+1, maxPos.x-minPos.x+1), adj))
			return false;

		pos = vec2i(int(flipped.y)+minPos.x, int(flipped.x)+minPos.y);
		return true;
	}

	void markBought(const vec2i& pos, Empire@ emp = null) {
		auto@ node = getNode(pos);
		if(node is null)
			return;

		node.bought = true;
		for(uint i = 0; i < 6; ++i) {
			vec2i otherPos = pos;
			if(doAdvance(otherPos, HexGridAdjacency(i))) {
				auto@ otherNode = getNode(otherPos);
				if(otherNode !is null && !otherNode.available) {
					otherNode.available = true;
					otherNode.stateChange(emp);
				}
			}
		}
	}

	void markUnlocked(const vec2i& pos, Empire@ emp = null) {
		auto@ node = getNode(pos);
		if(node is null)
			return;

		node.bought = true;
		node.unlocked = true;
		node.available = true;
		node.unlockable = true;
		for(uint i = 0; i < 6; ++i) {
			vec2i otherPos = pos;
			if(doAdvance(otherPos, HexGridAdjacency(i))) {
				auto@ otherNode = getNode(otherPos);
				if(otherNode !is null && (!otherNode.available || !otherNode.unlockable)) {
					otherNode.available = true;
					otherNode.unlockable = true;
					otherNode.stateChange(emp);
				}
			}
		}
	}
};

tidy final class TechnologyGridSpec {
	uint id;
	string ident;

	HexGridi indices;
	array<TechnologyNode@> nodes;

	vec2i minPos;
	vec2i maxPos;

	array<string> def_nodes;
	array<vec2i> def_positions;

	void resolve() {
		if(def_nodes.length == 0) {
			minPos = vec2i();
			maxPos = vec2i();
			return;
		}

		minPos = vec2i(INT_MAX, INT_MAX);
		maxPos = vec2i(INT_MIN, INT_MIN);

		for(uint i = 0, cnt = def_positions.length; i < cnt; ++i) {
			TechnologyNode node;
			node.position = def_positions[i];
			@node.type = getTechnology(def_nodes[i]);
			if(node.type is null) {
				error("Technology grid "+ident+" can't find technology "+def_nodes[i]);
				continue;
			}
			node.secret = node.type.secret;

			minPos.x = min(minPos.x, node.position.x);
			minPos.y = min(minPos.y, node.position.y);
			maxPos.x = max(maxPos.x, node.position.x);
			maxPos.y = max(maxPos.y, node.position.y);

			nodes.insertLast(node);
		}

		if(minPos.y % 2 != 0)
			minPos.y -= 1;

		indices.resize(maxPos.x - minPos.x + 1, maxPos.y - minPos.y + 1);
		indices.clear(-1);
		for(uint i = 0, cnt = nodes.length; i < cnt; ++i) {
			vec2u relPos = vec2u(nodes[i].position - minPos);
			if(!indices.valid(relPos))
				continue;
			indices[relPos] = int(i);
		}
	}

	TechnologyGrid@ create() const {
		TechnologyGrid grid;
		grid.nodes.length = nodes.length;
		grid.indices = indices;
		grid.minPos = minPos;
		grid.maxPos = maxPos;

		for(uint i = 0, cnt = nodes.length; i < cnt; ++i) {
			TechnologyNode@ spec = nodes[i];

			TechnologyNode n;
			n.id = int(i);
			@n.type = spec.type;
			n.position = spec.position;
			n.secret = spec.secret;

			if(n.type.dlc.length != 0) {
				if(!hasDLC(n.type.dlc)) {
					auto@ otherType = getTechnology(n.type.dlcReplace);
					if(otherType !is null)
						@n.type = otherType;
				}
			}

			@grid.nodes[i] = n;
		}

		for(uint i = 0, cnt = nodes.length; i < cnt; ++i) {
			if(nodes[i].type.defaultUnlock)
				grid.markUnlocked(nodes[i].position);
		}

		return grid;
	}
};

//}}}
//{{{ Subsystem modifiers
tidy final class TechAddModifier {
	string spec;
	array<const SubsystemDef@> subsys;
	string modifier;
	array<string> arguments;

	void apply(Empire@ emp, array<uint>@ ids = null) const {
		set_int improvedSubsystems;
		if(ids !is null)
			ids.length = 0;

		{
			WriteLock lock(emp.subsystemDataMutex);
			for(uint j = 0, jcnt = subsys.length; j < jcnt; ++j) {
				const SubsystemDef@ def = subsys[j];
				if(!def.hasModifier(modifier))
					continue;
				uint id = uint(-1);
				switch(arguments.length) {
					case 0:
						id = emp.addModifier(def, modifier); break;
					case 1:
						id = emp.addModifier(def, modifier, toFloat(arguments[0])); break;
					case 2:
						id = emp.addModifier(def, modifier, toFloat(arguments[0]), toFloat(arguments[1])); break;
					default:
						id = emp.addModifier(def, modifier, toFloat(arguments[0]), toFloat(arguments[1]), toFloat(arguments[2])); break;
				}
				if(ids !is null)
					ids.insertLast(id);
				improvedSubsystems.insert(def.index);
			}
		}
		
		//Auto-update all designs related to the improved subsystems
		//TODO: Shit's slow. Check index set overlap?
		if(!isShadow) {
			WriteLock lck(emp.designMutex);
			uint cnt = emp.designCount;
			for(uint i = 0; i < cnt; ++i) {
				const Design@ dsg = emp.designs[i];
				if(dsg.updated !is null)
					continue;
				uint sysCnt = dsg.subsystemCount;
				for(uint j = 0; j < sysCnt; ++j) {
					const SubsystemDef@ def = dsg.subsystems[j].type;
					if(improvedSubsystems.contains(def.index)) {
						emp.flagDesignOld(dsg);
						break;
					}
				}
			}
		}
	}

	void remove(Empire@ emp, array<uint>& ids) const {
		set_int improvedSubsystems;

		{
			WriteLock lock(emp.subsystemDataMutex);
			uint index = 0;
			for(uint j = 0, jcnt = min(subsys.length, ids.length); j < jcnt; ++j) {
				const SubsystemDef@ def = subsys[j];
				if(!def.hasModifier(modifier))
					continue;
				emp.removeModifier(def, ids[index++]);
				improvedSubsystems.insert(def.index);
			}
		}
		
		//Auto-update all designs related to the improved subsystems
		//TODO: Shit's slow. Check index set overlap?
		if(!isShadow) {
			WriteLock lck(emp.designMutex);
			uint cnt = emp.designCount;
			for(uint i = 0; i < cnt; ++i) {
				const Design@ dsg = emp.designs[i];
				if(dsg.updated !is null)
					continue;
				uint sysCnt = dsg.subsystemCount;
				for(uint j = 0; j < sysCnt; ++j) {
					const SubsystemDef@ def = dsg.subsystems[j].type;
					if(improvedSubsystems.contains(def.index)) {
						emp.flagDesignOld(dsg);
						break;
					}
				}
			}
		}
	}
}

TechAddModifier@ parseModifier(const string& value) {
	TechAddModifier modifier;

	string subsysName;
	int index = value.findFirst("::");
	if(index > 0) {
		modifier.spec = value;
		modifier.modifier = value.substr(index+2, value.length() - (index+2));

		subsysName = value.substr(0,index);
	}
	else {
		modifier.modifier = value;
	}

	int brkt = modifier.modifier.findFirst("(");
	if(brkt != -1) {
		string funcName;
		funcSplit(modifier.modifier, funcName, modifier.arguments);
		modifier.modifier = funcName;
	}

	if(subsysName.length == 0 || subsysName == "any")
		subsysName = "mod/"+modifier.modifier;

	parseSubsysSpec(modifier.subsys, subsysName);
	if(modifier.subsys.length == 0) {
		error(format("No subsystems matched '$2' / '$3'", value, subsysName));
		return null;
	}

	return modifier;
};

void parseSubsysSpec(array<const SubsystemDef@>@ list, const string& spec) {
	auto@ conds = spec.split(",");

	list.length = getSubsystemDefCount();
	for(uint i = 0, cnt = list.length; i < cnt; ++i)
		@list[i] = getSubsystemDef(i);
	for(uint i = 0, cnt = conds.length; i < cnt; ++i)
		filterSubsys(list, conds[i]);
}

void filterSubsys(array<const SubsystemDef@>@ list, const string& spec) {
	uint cnt = list.length;
	if(spec.startswith("tag/")) {
		string tag = spec.substr(4, spec.length - 4);
		for(uint i = 0; i < cnt; ++i) {
			if(!list[i].hasTag(tag)) {
				@list[i] = list[cnt-1];
				--cnt;
				--i;
			}
		}
		list.length = cnt;
	}
	else if(spec.startswith("module/")) {
		string mod = spec.substr(7, spec.length - 7);
		for(uint i = 0; i < cnt; ++i) {
			if(list[i].module(mod) is null) {
				@list[i] = list[cnt-1];
				--cnt;
				--i;
			}
		}
		list.length = cnt;
	}
	else if(spec.startswith("mod/")) {
		string mod = spec.substr(4, spec.length - 4);
		for(uint i = 0; i < cnt; ++i) {
			if(!list[i].hasModifier(mod)) {
				@list[i] = list[cnt-1];
				--cnt;
				--i;
			}
		}
		list.length = cnt;
	}
	else if(spec.startswith("hull/")) {
		string tag = spec.substr(5, spec.length - 5);
		for(uint i = 0; i < cnt; ++i) {
			if(!list[i].hasHullTag(tag)) {
				@list[i] = list[cnt-1];
				--cnt;
				--i;
			}
		}
		list.length = cnt;
	}
	else {
		//Single subsystem
		const SubsystemDef@ def = getSubsystemDef(spec);
		if(def !is null) {
			list.length = 1;
			@list[0] = def;
			cnt = 1;
		}
		else {
			list.length = 0;
			cnt = 0;
		}
	}
}
//}}}
//{{{ Data Files
array<TechnologyType@> techs;
dictionary techIdents;

int getTechnologyID(const string& ident) {
	TechnologyType@ type;
	techIdents.get(ident, @type);
	if(type !is null)
		return int(type.id);
	return -1;
}

string getTechnologyIdent(int id) {
	if(id < 0 || id >= int(techs.length))
		return "-";
	return techs[id].ident;
}

uint getTechnologyCount() {
	return techs.length;
}

const TechnologyType@ getTechnology(uint id) {
	if(id < techs.length)
		return techs[id];
	else
		return null;
}

const TechnologyType@ getTechnology(const string& name) {
	TechnologyType@ tech;
	techIdents.get(name, @tech);
	return tech;
}

void addTechnology(TechnologyType@ tech) {
	tech.id = techs.length;
	techs.insertLast(tech);
	techIdents.set(tech.ident, @tech);
}

void saveIdentifiers(SaveFile& file) {
	for(uint i = 0, cnt = techs.length; i < cnt; ++i) {
		auto@ type = techs[i];
		file.addIdentifier(SI_Technology, type.id, type.ident);
	}
}

array<TechnologyGridSpec@> grids;
dictionary gridIdents;

const TechnologyGridSpec@ getTechnologyGridSpec(uint id) {
	if(id < grids.length)
		return grids[id];
	else
		return null;
}

const TechnologyGridSpec@ getTechnologyGridSpec(const string& name) {
	TechnologyGridSpec@ tech;
	gridIdents.get(name, @tech);
	return tech;
}

void addTechnologyGridSpec(TechnologyGridSpec@ tech) {
	tech.id = grids.length;
	grids.insertLast(tech);
	gridIdents.set(tech.ident, @tech);
}

void parseLine(string& line, TechnologyType@ type, ReadFile@ file) {
	//Hook line
	auto@ hook = cast<ITechnologyHook>(parseHook(line, "research_effects::", instantiate=false, file=file));
	if(hook !is null)
		type.hooks.insertLast(hook);
}

void loadTech(TechnologyType@ type, ReadFile@ file, const string& key, const string& value) {
	if(key.equals_nocase("Name")) {
		type.name = localize(value);
	}
	else if(key.equals_nocase("Description")) {
		type.description = localize(value);
	}
	else if(key.equals_nocase("Blurb")) {
		type.blurb = localize(value);
	}
	else if(key.equals_nocase("Icon")) {
		type.icon = getSprite(value);
	}
	else if(key.equals_nocase("Symbol")) {
		type.symbol = getSprite(value);
	}
	else if(key.equals_nocase("Color")) {
		type.color = toColor(value);
	}
	else if(key.equals_nocase("Point Cost")) {
		type.pointCost = toDouble(value);
	}
	else if(key.equals_nocase("Time Cost")) {
		type.timeCost = toDouble(value);
	}
	else if(key.equals_nocase("Default Unlock")) {
		type.defaultUnlock = toBool(value);
	}
	else if(key.equals_nocase("Secondary Term")) {
		type.secondaryTerm = localize(value);
	}
	else if(key.equals_nocase("Secret")) {
		type.secret = toBool(value);
	}
	else if(key.equals_nocase("Category")) {
		type.category = value;
	}
	else if(key.equals_nocase("DLC")) {
		type.dlc = value;
	}
	else if(key.equals_nocase("DLC Replace")) {
		type.dlcReplace = value;
	}
	else if(key.equals_nocase("Secret Frequency")) {
		type.secretFrequency = toDouble(value);
	}
	else if(key.equals_nocase("Class")) {
		type.cls = getResearchClass(value);
	}
	else {
		parseLine(file.line, type, file);
	}
}

uint getResearchClass(const string& value) {
	if(value.equals_nocase("Boost")) {
		return Tech_Boost;
	}
	else if(value.equals_nocase("Upgrade")) {
		return Tech_Upgrade;
	}
	else if(value.equals_nocase("Unlock")) {
		return Tech_Unlock;
	}
	else if(value.equals_nocase("Keystone")) {
		return Tech_Keystone;
	}
	else if(value.equals_nocase("Special")) {
		return Tech_Special;
	}
	else if(value.equals_nocase("Secret")) {
		return Tech_Secret;
	}
	else if(value.equals_nocase("BigUpgrade")) {
		return Tech_BigUpgrade;
	}
	return Tech_Boost;
}

void loadGrid(TechnologyGridSpec@ grid, ReadFile@ file, const string& key, const string& value) {
	array<string>@ pos = value.split(",");
	if(pos.length != 2) {
		file.error("Invalid node specification.");
		return;
	}

	vec2i gridPos = vec2i(toInt(pos[0]), toInt(pos[1]));
	int index = grid.def_positions.find(gridPos);
	if(index != -1) {
		grid.def_nodes.removeAt(index);
		grid.def_positions.removeAt(index);
	}

	grid.def_nodes.insertLast(key);
	grid.def_positions.insertLast(gridPos);
}

void loadResearch(const string& filename) {
	ReadFile file(filename, true);

	string key, value;
	TechnologyType@ tech;
	TechnologyGridSpec@ grid;

	uint index = 0;
	while(file++) {
		if(file.fullLine) {
			if(tech !is null)
				parseLine(file.line, tech, file);
		}
		else if(file.key.equals_nocase("Technology")) {
			@tech = TechnologyType();
			@grid = null;
			tech.ident = file.value;
			addTechnology(tech);
		}
		else if(file.key.equals_nocase("Grid")) {
			@tech = null;
			@grid = null;
			if(!gridIdents.get(file.value, @grid)) {
				@grid = TechnologyGridSpec();
				grid.ident = file.value;
				addTechnologyGridSpec(grid);
			}
		}
		else if(file.key.equals_nocase("DLC") && tech is null) {
			if(!hasDLC(file.value))
				@grid = null;
		}
		else if(file.key.equals_nocase("Vanilla Only")) {
			if(toBool(value)) {
				if(isModdedGame && !path_inside("data", resolve("data/research/base_grid.txt")))
					@grid = null;
			}
		}
		else {
			if(grid !is null)
				loadGrid(grid, file, file.key, file.value);
			else if(tech !is null)
				loadTech(tech, file, file.key, file.value);
		}
	}
}

void preInit() {
	FileList list("data/research", "*.txt", true);
	for(uint i = 0, cnt = list.length; i < cnt; ++i)
		loadResearch(list.path[i]);
}

void init() {
	for(uint i = 0, cnt = techs.length; i < cnt; ++i) {
		auto@ type = techs[i];
		for(uint n = 0, ncnt = type.hooks.length; n < ncnt; ++n) {
			if(!cast<Hook>(type.hooks[n]).instantiate())
				error("Could not instantiate hook "+addrstr(type.hooks[n])+" on tech "+type.ident);
		}
	}
	for(uint i = 0, cnt = grids.length; i < cnt; ++i)
		grids[i].resolve();
}
//}}}
