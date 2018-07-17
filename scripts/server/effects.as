void DestroyShip(Event& evt) {
	evt.obj.destroy();
}

void ControlDestroyed(Event& evt) {
	Ship@ ship = cast<Ship>(evt.obj);

	//Make sure we still have a bridge or something with control up
	if(!ship.blueprint.hasTagActive(ST_ControlCore))
		ship.destroy();
}

void EngineBoost(Event& evt, double Duration, double Speed) {
	if(evt.custom1 > Duration * 0.5) {
		evt.obj.speedBoost(-Speed * evt.time * 2.0);
	}
	else {
		evt.obj.speedBoost(Speed * evt.time * 2.0);
		evt.custom1 += evt.time;
	}
}

void MissileStorm(Event& evt, double Duration, double Projectiles) {
	Ship@ ship = cast<Ship>(evt.obj);
	int sysIndex = evt.source_index;
	int effIndex = evt.destination_index;
	const Design@ dsg = ship.blueprint.design;
	const Effector@ efft = dsg.subsystems[sysIndex].effectors[effIndex];

	uint fire = round(Projectiles * evt.time);
	double tOff = 0.0, tStep = evt.time / double(fire);

	if(evt.target.hasLeaderAI) {
		uint supCnt = evt.target.supportCount;
		if(supCnt == 0) {
			for(uint i = 0; i < fire; ++i) {
				efft.trigger(evt.obj, evt.target, random3d(), 1.f, tOff);
				tOff += tStep;
			}
		}
		else {
			uint index = randomi(0, supCnt - 1);
			double chance = 5.0 / double(supCnt);
			for(uint i = 0; i < fire; ++i) {
				if(randomd() < chance) {
					efft.trigger(evt.obj, evt.target, random3d(), 1.f, tOff);
				}
				else {
					Object@ targ = evt.target.supportShip[i];
					if(targ !is null)
						efft.trigger(evt.obj, targ, random3d(), 1.f, tOff);
					else
						efft.trigger(evt.obj, evt.target, random3d(), 1.f, tOff);
					index = (index + 1) % supCnt;
				}
				tOff += tStep;
			}
		}
	}
	else {
		for(uint i = 0; i < fire; ++i) {
			efft.trigger(evt.obj, evt.target, random3d(), 1.f, tOff);
			tOff += tStep;
		}
	}
}

void StartFTLUpkeep(Event& evt, double amount) {
	evt.obj.owner.modFTLUse(+amount);
}

void EndFTLUpkeep(Event& evt, double amount) {
	evt.obj.owner.modFTLUse(-amount);
}

void LeakSupply(Event& evt, double LeakPctPerSec) {
	if(evt.workingPercent >= 0.9999f)
		return;
	Ship@ ship = cast<Ship>(evt.obj);
	if(ship is null || ship.Supply <= 0.0001f)
		return;

	ship.consumeSupplyPct(LeakPctPerSec * (1.0 - sqr(evt.workingPercent)) * evt.time);
}

void DestroyOnLowEfficiency(Event& evt, double threshold) {
	if(evt.workingPercent < threshold)
		evt.obj.destroy();
}
