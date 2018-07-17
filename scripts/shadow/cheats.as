bool CHEATS_ENABLED_THIS_GAME = false;
bool CHEATS_ENABLED = false;
bool getCheatsEnabled() {
	return CHEATS_ENABLED;
}

bool getCheatsEverOn() {
	return CHEATS_ENABLED_THIS_GAME;
}

void serverCheatsEnabled(bool enabled) {
	CHEATS_ENABLED = enabled;
	if(enabled)
		CHEATS_ENABLED_THIS_GAME = true;
}

void syncInitial(Message& msg) {
	msg >> CHEATS_ENABLED;
	msg >> CHEATS_ENABLED_THIS_GAME;
}
