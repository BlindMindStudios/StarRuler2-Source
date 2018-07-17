import bool getCheatsEverOn() from "cheats";

void clientAchive(string id) {
	if(!getCheatsEverOn())
		unlockAchievement(id);
}