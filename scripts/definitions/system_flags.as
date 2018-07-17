import saving;

array<string> systemFlags;
dictionary flagIdents;

uint getSystemFlagCount() {
	return systemFlags.length;
}

int getSystemFlag(const string& ident, bool create = true) {
	int id = -1;
	if(!flagIdents.get(ident, id) && create) {
		id = int(systemFlags.length);
		systemFlags.insertLast(ident);
		flagIdents.set(ident, id);
	}
	return id;
}

string getSystemFlagIdent(int id) {
	if(id < 0 || uint(id) >= systemFlags.length)
		return "";
	return systemFlags[id];
}

void saveIdentifiers(SaveFile& file) {
	for(uint i = 0, cnt = systemFlags.length; i < cnt; ++i)
		file.addIdentifier(SI_SystemFlag, int(i), systemFlags[i]);
}
