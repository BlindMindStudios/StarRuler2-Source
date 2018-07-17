bool hasGameEnded = false;

bool hasGameEnded_client() {
	return hasGameEnded;
}

void serverGameEnd() {
	hasGameEnded = true;
}

void syncInitial(Message& msg) {
	msg >> hasGameEnded;
}
