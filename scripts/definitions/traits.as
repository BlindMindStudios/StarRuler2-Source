#priority init 5500

#section game
import saving;
import hooks;
#section menu
class Hook {};
#section all

export Trait;
export getTrait, getTraitCount;

export TraitCategory;
export getTraitCategory, getTraitCategoryCount;

tidy final class Trait {
	uint id;
	const TraitCategory@ category;
	string ident;
	string name;
	string description;
	string unique;
	Sprite icon;
	Color color;
	int order = 0;

	int cost = 0;
	int gives = 0;
	bool defaultTrait = false;
	bool available = true;
	bool aiSupport = true;

	string dlc;

	array<ITraitEffect@> hooks;
	array<string> hookDefs;
	array<const Trait@> conflicts;
	array<string> conflictDefs;

	void preInit(Empire& emp, array<any>& data) const {
		data.length = hooks.length;
		for(uint i = 0, cnt = hooks.length; i < cnt; ++i)
			hooks[i].preInit(emp, data[i]);
	}

	void init(Empire& emp, array<any>& data) const {
		for(uint i = 0, cnt = hooks.length; i < cnt; ++i)
			hooks[i].init(emp, data[i]);
	}

	void postInit(Empire& emp, array<any>& data) const {
		data.length = hooks.length;
		for(uint i = 0, cnt = hooks.length; i < cnt; ++i)
			hooks[i].postInit(emp, data[i]);
	}

	void tick(Empire& emp, array<any>& data, double time) const {
		for(uint i = 0, cnt = hooks.length; i < cnt; ++i)
			hooks[i].tick(emp, data[i], time);
	}

	void save(array<any>& data, SaveFile& file) const {
		for(uint i = 0, cnt = hooks.length; i < cnt; ++i)
			hooks[i].save(data[i], file);
	}

	void load(array<any>& data, SaveFile& file) const {
		data.length = hooks.length;
		for(uint i = 0, cnt = hooks.length; i < cnt; ++i)
			hooks[i].load(data[i], file);
	}

	void addConflict(const Trait@ other) {
		if(conflicts.find(other) != -1)
			return;
		conflicts.insertLast(other);
	}

	bool get_hasDLC() const {
		if(dlc.length == 0)
			return true;
		return hasDLC(dlc);
	}

	bool hasConflicts(const array<const Trait@>& list) const {
		for(uint i = 0, cnt = list.length; i < cnt; ++i) {
			auto@ other = list[i];
			if(other is this)
				continue;
			if(conflicts.find(other) != -1)
				return true;
			if(unique.length != 0 && unique == other.unique)
				return true;
		}
		return false;
	}

	int opCmp(const Trait@ other) const {
		if(order < other.order)
			return -1;
		if(order > other.order)
			return 1;
		return 0;
	}

	bool opEquals(const Trait@ other) const {
		return other.id == id;
	}
};

interface ITraitEffect {
	void preInit(Empire& emp, any@ data) const;
	void init(Empire& emp, any@ data) const;
	void postInit(Empire& emp, any@ data) const;
	void tick(Empire& emp, any@ data, double time) const;
	void save(any@ data, SaveFile& file) const;
	void load(any@ data, SaveFile& file) const;
};

class TraitEffect : Hook, ITraitEffect {
	void preInit(Empire& emp, any@ data) const {}
	void init(Empire& emp, any@ data) const {}
	void postInit(Empire& emp, any@ data) const {}
	void tick(Empire& emp, any@ data, double time) const {}
	void save(any@ data, SaveFile& file) const {}
	void load(any@ data, SaveFile& file) const {}
};

array<Trait@> traits;
dictionary idents;

const Trait@ getTrait(uint id) {
	if(id >= traits.length)
		return null;
	return traits[id];
}

const Trait@ getTrait(const string& ident) {
	Trait@ def;
	if(idents.get(ident, @def))
		return def;
	return null;
}

int getTraitID(const string& ident) {
	auto@ type = getTrait(ident);
	if(type is null)
		return -1;
	return int(type.id);
}

string getTraitIdent(int id) {
	auto@ type = getTrait(id);
	if(type is null)
		return "";
	return type.ident;
}

uint getTraitCount() {
	return traits.length;
}

void addTrait(Trait@ type) {
	type.id = traits.length;
	traits.insertLast(type);
	idents.set(type.ident, @type);
}

tidy final class TraitCategory {
	uint id;
	string ident;
	string name;

	TraitCategory(const string& ident) {
		this.ident = ident;
		name = localize("#TRAIT_CAT_"+ident);
		if(name[0] == '#')
			name = ident;
	}
};

array<TraitCategory@> categories;
dictionary catIdents;

const TraitCategory@ getTraitCategory(uint id) {
	if(id >= categories.length)
		return null;
	return categories[id];
}

const TraitCategory@ getTraitCategory(const string& ident, bool create = false) {
	TraitCategory@ def;
	if(catIdents.get(ident, @def))
		return def;
	if(create)
		return addTraitCategory(TraitCategory(ident));
	return null;
}

uint getTraitCategoryCount() {
	return categories.length;
}

TraitCategory@ addTraitCategory(TraitCategory@ type) {
	type.id = categories.length;
	categories.insertLast(type);
	catIdents.set(type.ident, @type);
	return type;
}

void saveIdentifiers(SaveFile& file) {
#section game
	for(uint i = 0, cnt = traits.length; i < cnt; ++i) {
		auto type = traits[i];
		file.addIdentifier(SI_Trait, type.id, type.ident);
	}
#section all
}

void parseLine(string& line, Trait@ trait, ReadFile@ file) {
#section game
	//Hook line
	trait.hookDefs.insertLast(line);
#section all
}

void loadTraits(const string& filename) {
	ReadFile file(filename, true);
	
	string key, value;
	Trait@ trait;
	
	uint index = 0;
	while(file++) {
		key = file.key;
		value = file.value;
		
		if(file.fullLine) {
			string line = file.line;
			parseLine(line, trait, file);
		}
		else if(key.equals_nocase("Trait")) {
			if(trait !is null)
				addTrait(trait);
			@trait = Trait();
			trait.ident = value;
		}
		else if(trait is null) {
			file.error("Missing trait ID' line");
		}
		else if(key.equals_nocase("Name")) {
			trait.name = localize(value);
		}
		else if(key.equals_nocase("Description")) {
			trait.description = localize(value);
		}
		else if(key.equals_nocase("Costs Points")) {
			trait.cost = toInt(value);
		}
		else if(key.equals_nocase("Gives Points")) {
			trait.gives = toInt(value);
		}
		else if(key.equals_nocase("Category")) {
			@trait.category = getTraitCategory(value, create=true);
		}
		else if(key.equals_nocase("Icon")) {
			trait.icon = getSprite(value);
		}
		else if(key.equals_nocase("Color")) {
			trait.color = toColor(value);
		}
		else if(key.equals_nocase("Order")) {
			trait.order = toInt(value);
		}
		else if(key.equals_nocase("Unique")) {
			trait.unique = value;
		}
		else if(key.equals_nocase("Default")) {
			trait.defaultTrait = toBool(value);
		}
		else if(key.equals_nocase("Available")) {
			trait.available = toBool(value);
		}
		else if(key.equals_nocase("Conflict")) {
			trait.conflictDefs.insertLast(value);
		}
		else if(key.equals_nocase("DLC")) {
			trait.dlc = value;
		}
		else if(key.equals_nocase("AI Support")) {
			trait.aiSupport = toBool(value);
		}
		else {
			string line = file.line;
			parseLine(line, trait, file);
		}
	}
	
	if(trait !is null)
		addTrait(trait);
}

export initTraits;
bool initialized = false;
void initTraits() {
	if(initialized)
		return;
	initialized = true;
	FileList list("data/traits", "*.txt", true);
	for(uint i = 0, cnt = list.length; i < cnt; ++i)
		loadTraits(list.path[i]);
}

void preInit() {
	initTraits();
#section game
	for(uint i = 0, cnt = traits.length; i < cnt; ++i) {
		auto@ trait = traits[i];

		for(uint n = 0, ncnt = trait.hookDefs.length; n < ncnt; ++n) {
			auto@ hook = cast<ITraitEffect>(parseHook(trait.hookDefs[n], "trait_effects::", instantiate=false));
			if(hook !is null)
				trait.hooks.insertLast(hook);
		}
	}
#section all
}

void init() {
	for(uint i = 0, cnt = traits.length; i < cnt; ++i) {
		auto@ trait = traits[i];

#section game
		for(uint n = 0, ncnt = trait.hooks.length; n < ncnt; ++n) {
			if(!cast<Hook>(trait.hooks[n]).instantiate())
				error("Could not instantiate hook "+addrstr(trait.hooks[n])+" on trait "+trait.ident);
		}
#section all

		for(uint n = 0, ncnt = trait.conflictDefs.length; n < ncnt; ++n) {
			Trait@ other;
			if(!idents.get(trait.conflictDefs[n], @other)) {
				error("Could not find conflict trait "+trait.conflictDefs[n]+" in trait "+trait.ident);
				continue;
			}

			trait.addConflict(other);
			other.addConflict(trait);
		}
	}
}
