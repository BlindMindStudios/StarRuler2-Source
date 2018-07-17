bool hasProposedPeace(Player& player, Empire& from, Empire& to) {
	if(player.emp !is from && player.emp !is to)
		return false;
	return from.PeaceMask.value & to.mask != 0;
}

bool isForcedPeace(Player& player, Empire& from, Empire& to) {
	if(player.emp !is from && player.emp !is to)
		return false;
	return from.ForcedPeaceMask.value & to.mask != 0;
}
