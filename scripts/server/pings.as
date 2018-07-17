
void sendPingAll(Player& pl, vec3d position, uint type = 0) {
	sendPing(pl.emp, position, type, alliesOnly=false);
}

void sendPingAllied(Player& pl, vec3d position, uint type = 0) {
	sendPing(pl.emp, position, type, alliesOnly=true);
}

void sendPing(Empire@ fromEmp, vec3d position, uint type = 0, bool alliesOnly = true) {
	auto@ players = getPlayers();

	//Send to empires
	for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i) {
		Empire@ other = getEmpire(i);
		if(!other.major)
			continue;
		if(other !is fromEmp) {
			if(fromEmp.ContactMask & other.mask == 0)
				continue;
			if(alliesOnly) {
				bool isAlly = false;
				if(fromEmp.ForcedPeaceMask & other.mask != 0)
					isAlly = true;
				else if(fromEmp.SubjugatedBy is other)
					isAlly = true;
				else if(other.SubjugatedBy is fromEmp)
					isAlly = true;
				if(!isAlly)
					continue;
			}
		}
		other.aiPing(fromEmp, position, type);
		if(other.player !is null)
			showPing(other.player, fromEmp, position, type);
	}

	//Send to spectators
	for(uint i = 0, cnt = players.length; i < cnt; ++i) {
		auto@ other = players[i];
		if(other.emp is spectatorEmpire)
			showPing(other, fromEmp, position, type);
	}
}
