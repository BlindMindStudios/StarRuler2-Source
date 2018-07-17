import notifications;

void declareWar(Player& player, Empire& onEmpire) {
	Empire@ emp = player.emp;
	if(emp is null)
		return;
	declareWar(emp, onEmpire);
}

void declareWar(Empire@ emp, Empire& onEmpire) {
	if(emp.ContactMask & onEmpire.mask == 0)
		return;
	if(emp.SubjugatedBy !is null || onEmpire.SubjugatedBy !is null)
		return;
	//Check if peace is forced
	if(emp.ForcedPeaceMask.value & onEmpire.mask != 0)
		return;

	//Declare actual war
	emp.setHostile(onEmpire, true);

	onEmpire.setHostile(emp, true);

	onEmpire.notifyWarStatus(emp, WST_War);
}

bool isForcedPeace(Player& player, Empire& from, Empire& to) {
	if(player.emp !is from && player.emp !is to)
		return false;
	return from.ForcedPeaceMask.value & to.mask != 0;
}

void forcePeace(Empire& from, Empire& to) {
	from.ForcedPeaceMask |= to.mask;
	to.ForcedPeaceMask |= from.mask;

	from.setHostile(to, false);
	to.setHostile(from, false);
}

void endForcedPeace(Empire& from, Empire& to) {
	from.ForcedPeaceMask &= ~to.mask;
	to.ForcedPeaceMask &= ~from.mask;
}
