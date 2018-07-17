import bool getCheatsEverOn() from "cheats";

void giveAchievement(Empire@ emp, const string &in id) {
	if(!emp.valid || getCheatsEverOn())
		return;
	if(emp is playerEmpire)
		unlockAchievement(id);
	if(mpServer && emp.player !is null)
		clientAchievement(emp.player, id);
}