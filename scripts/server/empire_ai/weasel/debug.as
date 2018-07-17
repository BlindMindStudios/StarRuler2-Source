import empire_ai.weasel.WeaselAI;
import empire_ai.weasel.Colonization;
import empire_ai.weasel.Construction;
import empire_ai.weasel.Budget;
import empire_ai.weasel.Designs;
import empire_ai.weasel.Development;
import empire_ai.weasel.Fleets;
import empire_ai.weasel.Military;
import empire_ai.weasel.Planets;
import empire_ai.weasel.Resources;
import empire_ai.weasel.Scouting;
import empire_ai.weasel.Systems;
import empire_ai.weasel.Creeping;
import empire_ai.weasel.Movement;
import empire_ai.weasel.Relations;
import empire_ai.weasel.Intelligence;
import empire_ai.weasel.War;
import empire_ai.weasel.Research;
import empire_ai.weasel.Energy;
import empire_ai.weasel.Diplomacy;
import empire_ai.weasel.ftl.Gate;
import empire_ai.weasel.ftl.Hyperdrive;
import empire_ai.weasel.ftl.Fling;
import empire_ai.weasel.ftl.Slipstream;
import empire_ai.weasel.ftl.Jumpdrive;
import empire_ai.weasel.race.Verdant;
import empire_ai.weasel.race.Mechanoid;
import empire_ai.weasel.race.StarChildren;
import empire_ai.weasel.race.Extragalactic;
import empire_ai.weasel.race.Linked;
import empire_ai.weasel.race.Devout;
import empire_ai.weasel.race.Ancient;
import empire_ai.weasel.misc.Invasion;
import empire_ai.EmpireAI;

AI@ ai(uint index) {
	Empire@ emp = getEmpire(index);
	return cast<AI>(cast<EmpireAI>(emp.EmpireAI).ctrl);
}

Colonization@ colonization(uint index) {
	return cast<Colonization>(ai(index).colonization);
}

Construction@ construction(uint index) {
	return cast<Construction>(ai(index).construction);
}

Budget@ budget(uint index) {
	return cast<Budget>(ai(index).budget);
}

Designs@ designs(uint index) {
	return cast<Designs>(ai(index).designs);
}

Development@ development(uint index) {
	return cast<Development>(ai(index).development);
}

Fleets@ fleets(uint index) {
	return cast<Fleets>(ai(index).fleets);
}

Military@ military(uint index) {
	return cast<Military>(ai(index).military);
}

Planets@ planets(uint index) {
	return cast<Planets>(ai(index).planets);
}

Resources@ resources(uint index) {
	return cast<Resources>(ai(index).resources);
}

Scouting@ scouting(uint index) {
	return cast<Scouting>(ai(index).scouting);
}

Systems@ systems(uint index) {
	return cast<Systems>(ai(index).systems);
}

Movement@ movement(uint index) {
	return cast<Movement>(ai(index).movement);
}

Creeping@ creeping(uint index) {
	return cast<Creeping>(ai(index).creeping);
}

Relations@ relations(uint index) {
	return cast<Relations>(ai(index).relations);
}

Intelligence@ intelligence(uint index) {
	return cast<Intelligence>(ai(index).intelligence);
}

War@ war(uint index) {
	return cast<War>(ai(index).war);
}

Research@ research(uint index) {
	return cast<Research>(ai(index).research);
}

Energy@ energy(uint index) {
	return cast<Energy>(ai(index).energy);
}

Diplomacy@ diplomacy(uint index) {
	return cast<Diplomacy>(ai(index).diplomacy);
}

Gate@ gate(uint index) {
	return cast<Gate>(ai(index).ftl);
}

Hyperdrive@ hyperdrive(uint index) {
	return cast<Hyperdrive>(ai(index).ftl);
}

Fling@ fling(uint index) {
	return cast<Fling>(ai(index).ftl);
}

Slipstream@ slipstream(uint index) {
	return cast<Slipstream>(ai(index).ftl);
}

Jumpdrive@ jumpdrive(uint index) {
	return cast<Jumpdrive>(ai(index).ftl);
}

Mechanoid@ mechanoid(uint index) {
	return cast<Mechanoid>(ai(index).race);
}

Verdant@ verdant(uint index) {
	return cast<Verdant>(ai(index).race);
}

StarChildren@ starchildren(uint index) {
	return cast<StarChildren>(ai(index).race);
}

Extragalactic@ extragalactic(uint index) {
	return cast<Extragalactic>(ai(index).race);
}

Linked@ linked(uint index) {
	return cast<Linked>(ai(index).race);
}

Devout@ devout(uint index) {
	return cast<Devout>(ai(index).race);
}

Ancient@ ancient(uint index) {
	return cast<Ancient>(ai(index).race);
}

Invasion@ invasion(uint index) {
	return cast<Invasion>(ai(index).invasion);
}
