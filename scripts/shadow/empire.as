import ftl;
import empire_data;

uint majorEmpireCount = 0;

uint getMajorEmpireCount() {
	return majorEmpireCount;
}

void recvPeriodic(Empire& emp, Message& msg) {
	if(!msg.readBit())
		return;
	msg >> emp.visionMask >> emp.hostileMask;
	emp.cacheVision();
	msg >> emp.GlobalLoyalty.value;
	emp.Victory = msg.readSignedSmall();
	emp.readResources(msg);
	if(msg.readBit())
		emp.readAbilityDelta(msg);
	emp.readNotifications(msg, true);
	emp.readResearch(msg);
	emp.readInfluenceManager(msg);
	emp.readAttributes(msg);
	emp.readObjects(msg);
	emp.readSyncedStates(msg);
	emp.readEvents(msg);
	emp.readDelta(msg);
	emp.readAttitudes(msg, false);
}

void syncInitial(Empire& emp, Message& msg) {
	emp.readNotifications(msg, false);
	emp.readInfluenceManager(msg);
	emp.readAttributes(msg);
	emp.readObjects(msg);
	emp.readResearch(msg);
	emp.readSyncedStates(msg);
	emp.readAbilities(msg);
	emp.readTraits(msg);
	emp.readAttitudes(msg, true);
	emp.readEvents(msg);

	msg >> emp.major;
	msg >> emp.backgroundDef;
	msg >> emp.portraitDef;
	msg >> emp.flagDef;
	msg >> emp.flagID;
	msg >> emp.RaceName;
	msg >> emp.ColonizerModel;
	msg >> emp.ColonizerMaterial;

	@emp.background = getMaterial(emp.backgroundDef);
	
	auto@ flag = getEmpireFlag(emp.flagDef);
	if(flag is null)
		@flag = getEmpireFlag(emp.id % getEmpireFlagCount());
	@emp.flag = flag.flag;
	
	@emp.portrait = getMaterial(emp.portraitDef);
	if(emp.portrait is material::error)
		@emp.portrait = getEmpirePortrait(randomi(0, getEmpirePortraitCount()-1)).portrait;
}

void recvPeriodic(Message& msg) {
	uint cnt = getEmpireCount();
	for(uint i = 0; i < cnt; ++i)
		recvPeriodic(getEmpire(i), msg);
}

void init() {
	spectatorEmpire.visionMask = 0;
	spectatorEmpire.ContactMask.value = int(~0);
}

void tick(double time) {
	uint cnt = getEmpireCount();
	for(uint i = 0; i < cnt; ++i) {
		Empire@ emp = getEmpire(i);
		emp.influenceTick(time);
	}
}

void syncInitial(Message& msg) {
	uint cnt = getEmpireCount();
	for(uint i = 0; i < cnt; ++i) {
		Empire@ emp = getEmpire(i);
		syncInitial(emp, msg);
		if(emp.major)
			++majorEmpireCount;
	}
}

void allowPlayEmpire(Empire@ emp) {
	if(emp is spectatorEmpire)
		spectatorEmpire.visionMask = ~0;
	@playerEmpire = emp;
	CURRENT_PLAYER.linkEmpire(emp);
	playingEmpire(emp);
}
