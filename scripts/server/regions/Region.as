import saving;
import Node@ getCullingNode(const vec3d& pos) from "map_generation";
import system_flags;

tidy class RegionScript {
	bool delta = false;

	array<int> systemFlags(getEmpireCount() * getSystemFlagCount(), 0);
	bool flagDelta = false;

	void postInit(Region& region) {
		region.initRegion();
	}

	void save(Region& region, SaveFile& file) {
		file << cast<Savable>(region.RegionObjects);
		file << region.AngleOffset;
		file << region.InnerRadius;
		file << region.OuterRadius;
		file << region.SystemId;
		file << region.PrimaryEmpire;
		file << region.TradeMask;
		file << region.PlanetsMask;
		file << region.MemoryMask;
		file << region.VisionMask;
		file << region.ShipyardMask;
		file << region.ProtectedMask;
		file << region.FreeFTLMask;
		file << region.SiegedMask;
		file << region.SiegingMask;
		file << region.CoreSystemMask;
		file << region.GateMask.value;
		file << region.BasicVisionMask;
		file << region.TargetCostMod;
		file << region.BlockFTLMask.value;
		file << region.EngagedMask;
		file << region.CombatMask;
		file << region.SeenMask;

		file << region.ScoutingMask.value;
		file << region.ExploredMask.value;

		uint fCount = getSystemFlagCount();
		file << fCount;
		for(uint i = 0; i < fCount; ++i) {
			file.writeIdentifier(SI_SystemFlag, i);
			for(uint n = 0, ncnt = getEmpireCount(); n < ncnt; ++n)
				file << systemFlags[i*ncnt + n];
		}
	}

	void load(Region& region, SaveFile& file) {
		file >> cast<Savable>(region.RegionObjects);
		file >> region.AngleOffset;
		file >> region.InnerRadius;
		file >> region.OuterRadius;
		file >> region.SystemId;
		file >> region.PrimaryEmpire;
		file >> region.TradeMask;
		if(file >= SV_0059) {
			file >> region.PlanetsMask;
			file >> region.MemoryMask;
		}
		file >> region.VisionMask;
		file >> region.ShipyardMask;
		file >> region.ProtectedMask;
		file >> region.FreeFTLMask;
		file >> region.SiegedMask;
		file >> region.SiegingMask;
		file >> region.CoreSystemMask;
		file >> region.GateMask.value;
		file >> region.BasicVisionMask;
		file >> region.TargetCostMod;
		file >> region.BlockFTLMask.value;
		file >> region.EngagedMask;
		file >> region.CombatMask;
		if(file >= SV_0047)
			file >> region.SeenMask;
		else
			region.SeenMask = region.VisionMask;

		if(file >= SV_0099) {
			file >> region.ScoutingMask.value;
			file >> region.ExploredMask.value;
		}
		else {
			region.ExploredMask.value = int(~0);
		}
	
		bindCullingNode(region, region.position, region.radius+128.0);

		if(file >= SV_0094) {
			uint fCount = 0;
			file >> fCount;
			for(uint i = 0; i < fCount; ++i) {
				uint index = file.readIdentifier(SI_SystemFlag);
				if(index < getSystemFlagCount()) {
					for(uint n = 0, ncnt = getEmpireCount(); n < ncnt; ++n)
						file >> systemFlags[index*ncnt + n];
				}
				else {
					int dummy = 0;
					for(uint n = 0, ncnt = getEmpireCount(); n < ncnt; ++n)
						file >> dummy;
				}
			}
		}
	}

	void postLoad(Region& region) {
		region.regionPostLoad();
		auto cnode = region.getNode();
		if(cnode !is null)
			cnode.reparent(getCullingNode(region.position));
	}

	double tick(Region& region, double time) {
		region.tickRegion(time);
		return 0.2;
	}
	
	void writeTypicalMask(Message& msg, uint mask) const {
		msg.writeBit(mask != 0);
		if(mask != 0)
			msg << mask;
	}
	
	void writeMasks(const Region& region, Message& msg) {
		msg << region.VisionMask;
		
		writeTypicalMask(msg, region.ProtectedMask.value);
		writeTypicalMask(msg, region.FreeFTLMask.value);
		writeTypicalMask(msg, region.SiegedMask.value);
		writeTypicalMask(msg, region.SiegingMask.value);
		writeTypicalMask(msg, region.GateMask.value);
		writeTypicalMask(msg, region.BlockFTLMask.value);
		writeTypicalMask(msg, region.CombatMask);
		writeTypicalMask(msg, region.TradeMask);
		writeTypicalMask(msg, region.MemoryMask);
		writeTypicalMask(msg, region.ExploredMask.value);
	}

	void syncInitial(const Region& region, Message& msg) {
		msg.writeSmall(region.SystemId);
		msg.writeFixed(region.AngleOffset, 0.0, twopi);
		msg << region.OuterRadius;
		msg.writeFixed(region.InnerRadius, 0.0, region.OuterRadius);
		msg.writeSignedSmall(region.TargetCostMod);
		
		writeMasks(region, msg);

		msg.writeSmall(systemFlags.length);
		for(uint i = 0, cnt = systemFlags.length; i < cnt; ++i)
			msg.writeBit(systemFlags[i] > 0);
	}

	bool getSystemFlag(Empire@ emp, uint flagIndex) const {
		if(emp is null || !emp.valid)
			return false;
		if(flagIndex >= getSystemFlagCount())
			return false;
		return systemFlags[flagIndex * getEmpireCount() + emp.index] > 0;
	}

	bool getSystemFlagAny(uint flagIndex) const {
		if(flagIndex >= getSystemFlagCount())
			return false;
		for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i) {
			if(systemFlags[flagIndex * cnt + i] > 0)
				return true;
		}
		return false;
	}

	void setSystemFlag(Empire@ emp, uint flagIndex, bool value) {
		if(emp is null || !emp.valid)
			return;
		if(flagIndex >= getSystemFlagCount())
			return;
		systemFlags[flagIndex * getEmpireCount() + emp.index] += value ? +1 : -1;
		flagDelta = true;
	}

	void syncDetailed(const Region& region, Message& msg) {
		msg.writeSignedSmall(region.TargetCostMod);
		
		writeMasks(region, msg);

		msg.writeSmall(systemFlags.length);
		for(uint i = 0, cnt = systemFlags.length; i < cnt; ++i)
			msg.writeBit(systemFlags[i] > 0);
	}

	void modTargetCostMod(Region& region, int mod) {
		region.TargetCostMod += mod;
		delta = true;
	}

	int prevProtected = 0, prevFTL = 0, prevSieged = 0, prevSieging = 0, prevGate = 0, prevBlock = 0, prevCombat = 0;
	uint prevVision = 0, prevTrade = 0;
	
	bool syncDelta(const Region& region, Message& msg) {
		bool used = false;
		if(prevProtected != region.ProtectedMask.value || prevFTL != region.FreeFTLMask.value
				|| prevSieged != region.SiegedMask.value || prevSieging != region.SiegingMask.value
				|| prevVision != region.VisionMask || prevGate != region.GateMask.value
				|| prevBlock != region.BlockFTLMask.value || prevCombat != region.CombatMask
				|| prevTrade != region.TradeMask
				|| delta)
		{
			msg.write1();
			msg.writeSignedSmall(region.TargetCostMod);
			writeMasks(region, msg);
			
			prevProtected = region.ProtectedMask.value;
			prevFTL = region.FreeFTLMask.value;
			prevSieged = region.SiegedMask.value;
			prevSieging = region.SiegingMask.value;
			prevVision = region.VisionMask;
			prevGate = region.GateMask.value;
			prevBlock = region.BlockFTLMask.value;
			prevCombat = region.CombatMask;
			prevTrade = region.TradeMask;
			delta = false;
			used = true;
		}
		else {
			msg.write0();
		}
		if(flagDelta) {
			used = true;
			flagDelta = false;
			msg.write1();
			for(uint i = 0, cnt = systemFlags.length; i < cnt; ++i)
				msg.writeBit(systemFlags[i] > 0);
		}
		else {
			msg.write0();
		}
		return used;
	}
};
