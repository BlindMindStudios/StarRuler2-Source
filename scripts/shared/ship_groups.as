enum EngagementRange {
	ER_FlagshipMin,
	ER_FlagshipMax,
	ER_SupportMin,
	ER_RaidingOnly,
};

enum EngagementBehaviour {
	EB_CloseIn,
	EB_KeepDistance,
};

enum AutoMode {
	AM_HoldPosition,
	AM_AreaBound,
	AM_Unbound,
	AM_RegionBound,
	AM_HoldFire,
};

enum AutoState {
	AS_None,
	AS_Attacking,
	AS_Returning,
};

final class GroupData : Serializable, Savable {
	const Design@ dsg;

	//Ships that are currently alive
	uint amount = 0;

	//Ships that have died in the past
	uint ghost = 0;

	//Ships that have been paid for but
	//need to be constructed on nearby shipyards
	uint ordered = 0;

	//Amount of ships that have already been
	//ordered and are awaiting completion
	uint waiting = 0;

	//Ships ordered in a particular budget cycle for refunding
	int orderCycle = -1;
	uint orderAmount = 0;

	uint get_totalSize() {
		return amount + ordered + ghost;
	}

	void read(Message& msg) {
		msg >> dsg;
		amount = msg.readSmall();
		ghost = msg.readSmall();
		ordered = msg.readSmall();
		waiting = msg.readSmall();
	}

	void write(Message& msg) {
		msg << dsg;
		msg.writeSmall(amount);
		msg.writeSmall(ghost);
		msg.writeSmall(ordered);
		msg.writeSmall(waiting);
	}

	void load(SaveFile& msg) {
		msg >> dsg;
		msg >> amount;
		msg >> ghost;
		msg >> ordered;
		msg >> waiting;
		msg >> orderCycle;
		msg >> orderAmount;
	}

	void save(SaveFile& msg) {
		msg << dsg;
		msg << amount;
		msg << ghost;
		msg << ordered;
		msg << waiting;
		msg << orderCycle;
		msg << orderAmount;
	}
};
