import version;

void init() {
	string ver = SCRIPT_VERSION;
	int pos = ver.findLast(" ");
	if(pos != -1)
		ver = ver.substr(pos+2);
	else if(ver.length != 0)
		ver = ver.substr(1);
	errorVersion = toUInt(ver);
}
