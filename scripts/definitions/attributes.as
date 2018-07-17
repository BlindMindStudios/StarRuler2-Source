import saving;

enum AttributeComp {
	AC_Add,
	AC_AddBase,
	AC_AddFactor,
	AC_Multiply,

	AC_INVALID
};

AttributeComp getAttributeMode(const string& str) {
	if(str.equals_nocase("add"))
		return AC_Add;
	if(str.equals_nocase("addbase"))
		return AC_AddBase;
	if(str.equals_nocase("addfactor"))
		return AC_AddFactor;
	if(str.equals_nocase("multiply"))
		return AC_Multiply;
	return AC_INVALID;
}

string getAttributeModeIdent(int id) {
	switch(id) {
		case AC_Add: return "Add";
		case AC_AddBase: return "AddBase";
		case AC_AddFactor: return "AddFactor";
		case AC_Multiply: return "Multiply";
	}
	return "Invalid";
}

//Attributes are computed as:
// attrib = ((Base + AddBase) * (1 + AddFactor) + Add) * Multiply
//  Modifies for anything but Multiply is additive, Multiply is multiplicative.

array<string> dynAttributes;
dictionary attribIdents;

uint getEmpAttributeCount() {
	return dynAttributes.length + EA_COUNT;
}

int getEmpAttribute(const string& ident, bool create = true) {
	int id = ::getEmpireAttribute(ident);
	if(id != -1)
		return id;
	if(!attribIdents.get(ident, id) && create) {
		id = int(dynAttributes.length) + EA_COUNT;
		dynAttributes.insertLast(ident);
		attribIdents.set(ident, id);
	}
	return id;
}

string getEmpAttributeIdent(int id) {
	if(id < EA_COUNT)
		return getEmpireAttributeName(id);
	if(uint(id - EA_COUNT) >= dynAttributes.length)
		return "";
	return dynAttributes[id - EA_COUNT];
}

void saveIdentifiers(SaveFile& file) {
	for(uint i = 0; i < EA_COUNT; ++i)
		file.addIdentifier(SI_EmpAttribute, int(i), getEmpireAttributeName(i));
	for(uint i = 0, cnt = dynAttributes.length; i < cnt; ++i)
		file.addIdentifier(SI_EmpAttribute, int(EA_COUNT + i), dynAttributes[i]);
}
