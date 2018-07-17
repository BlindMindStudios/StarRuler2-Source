void setGameSpeed(Player& pl, double speed) {
	if(pl != HOST_PLAYER)
		return;

	gameSpeed = clamp(speed, 0.0, 10.0);
}
