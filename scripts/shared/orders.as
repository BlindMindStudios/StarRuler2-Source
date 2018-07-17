enum OrderType {
	OT_Attack,
	OT_Goto,
	OT_Hyperdrive,
	OT_Move,
	OT_PickupOrder,
	OT_Capture,
	OT_Scan,
	OT_Refresh,
	OT_Fling,
	OT_OddityGate,
	OT_Slipstream,
	OT_Ability,
	OT_AutoExplore,
	OT_Wait,
	OT_Jumpdrive,
	OT_INVALID
};

bool isFTLOrder(uint type) {
	return type == OT_Hyperdrive || type == OT_Slipstream || type == OT_Fling || type == OT_Jumpdrive;
}

class OrderDesc : Serializable {
	uint type;
	bool hasMovement;
	vec3d moveDestination;

	void write(Message& msg) {
		msg << uint(type);
		if(hasMovement) {
			msg.write1();
			msg << moveDestination;
		}
		else {
			msg.write0();
		}
	}

	void read(Message& msg) {
		msg >> type;
		hasMovement = msg.readBit();
		if(hasMovement)
			msg >> moveDestination;
	}
};
