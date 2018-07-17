tidy class RegionScript {
	array<bool> systemFlags;

	void init(Region& region) {
		region.initRegion();
	}

	double tick(Region& region, double time) {
		region.tickRegion(time);
		return 0.2;
	}
	
	uint readTypicalMask(Message& msg) const {
		if(msg.readBit())
			return msg.read_uint();
		else
			return 0;
	}

	bool getSystemFlag(Empire@ emp, uint flagIndex) const {
		if(emp is null || !emp.valid)
			return false;
		uint ind = flagIndex * getEmpireCount() + emp.index;
		if(ind >= systemFlags.length)
			return false;
		return systemFlags[ind];
	}

	bool getSystemFlagAny(uint flagIndex) const {
		for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i) {
			uint ind = flagIndex * getEmpireCount() + i;
			if(ind < systemFlags.length && systemFlags[ind])
				return true;
		}
		return false;
	}
	
	void readMasks(Region& region, Message& msg) {
		msg >> region.VisionMask;
		
		region.ProtectedMask.value = readTypicalMask(msg);
		region.FreeFTLMask.value = readTypicalMask(msg);
		region.SiegedMask.value = readTypicalMask(msg);
		region.SiegingMask.value = readTypicalMask(msg);
		region.GateMask.value = readTypicalMask(msg);
		region.BlockFTLMask.value = readTypicalMask(msg);
		region.CombatMask = readTypicalMask(msg);
		region.TradeMask = readTypicalMask(msg);
		region.MemoryMask = readTypicalMask(msg);
		region.ExploredMask.value = readTypicalMask(msg);
	}

	void syncInitial(Region& region, Message& msg) {
		region.SystemId = msg.readSmall();
		region.AngleOffset = msg.readFixed(0.0, twopi);
		msg >> region.OuterRadius;
		region.InnerRadius = msg.readFixed(0.0, region.OuterRadius);
		region.TargetCostMod = msg.readSignedSmall();
		
		readMasks(region, msg);
		
		region.updateRegionPlane();

		systemFlags.length = msg.readSmall();
		for(uint i = 0, cnt = systemFlags.length; i < cnt; ++i)
			systemFlags[i] = msg.readBit();
	}

	void syncDetailed(Region& region, Message& msg, double tDiff) {
		region.TargetCostMod = msg.readSignedSmall();
		
		readMasks(region, msg);
		region.updateRegionPlane();

		systemFlags.length = msg.readSmall();
		for(uint i = 0, cnt = systemFlags.length; i < cnt; ++i)
			systemFlags[i] = msg.readBit();
	}

	void syncDelta(Region& region, Message& msg, double tDiff) {
		if(msg.readBit()) {
			region.TargetCostMod = msg.readSignedSmall();
			readMasks(region, msg);
			region.updateRegionPlane();
		}
		if(msg.readBit()) {
			for(uint i = 0, cnt = systemFlags.length; i < cnt; ++i)
				systemFlags[i] = msg.readBit();
		}
	}
};
