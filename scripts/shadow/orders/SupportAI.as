tidy class SupportAI : Component_SupportAI {
	void readSupportAI(Object& obj, Message& msg) {
		Ship@ ship = cast<Ship>(obj);
		@ship.Leader = msg.readObject();
	}

	void readSupportAIDelta(Object& obj, Message& msg) {
		Ship@ ship = cast<Ship>(obj);
		@ship.Leader = msg.readObject();
	}
}
