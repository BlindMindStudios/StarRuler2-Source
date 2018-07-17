#priority init 10000
import saving;

const array<string> dlcs = {"Heralds"};

#section client
int getUnlockTag(const string& ident, bool create = true) {
	return getUnlockTag_client(ident);
}

string getUnlockTagIdent(int id) {
	return getUnlockTagIdent_client(id);
}

#section server-side
array<string> unlockTags;
dictionary unlockIdents;

void preInit() {
	for(uint i = 0, cnt = dlcs.length; i < cnt; ++i)
		getUnlockTag(dlcs[i]+"DLC", create=true);
}

uint getUnlockTagCount() {
	return unlockTags.length;
}

int getUnlockTag(const string& ident, bool create = true) {
	int id = -1;
	if(!unlockIdents.get(ident, id) && create) {
		id = int(unlockTags.length);
		unlockTags.insertLast(ident);
		unlockIdents.set(ident, id);
	}
	return id;
}

int getUnlockTag_client(string ident) {
	int id = -1;
	if(unlockIdents.get(ident, id))
		return id;
	return -1;
}

string getUnlockTagIdent(int id) {
	if(id < 0 || uint(id) >= unlockTags.length)
		return "";
	return unlockTags[id];
}

void saveIdentifiers(SaveFile& file) {
	for(uint i = 0, cnt = unlockTags.length; i < cnt; ++i)
		file.addIdentifier(SI_UnlockTag, int(i), unlockTags[i]);
}
