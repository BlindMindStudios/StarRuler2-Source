import statuses;

uint typeMask = DF_Flag1 | DF_Flag2;

enum DamageTypes {
	DT_Generic = 0,
	DT_Projectile,
	DT_Energy,
	DT_Explosive,
};

DamageFlags DF_IgnoreDR = DF_Flag3;
DamageFlags ReachedInternals = DF_Flag4;
DamageFlags DF_FullDR = DF_Flag5;


void Damage(Event& evt, double Amount) {
	DamageEvent dmg;
	dmg.damage = Amount * double(evt.efficiency) * double(evt.partiality);
	dmg.partiality = evt.partiality;
	dmg.impact = evt.impact;

	@dmg.obj = evt.obj;
	@dmg.target = evt.target;
	dmg.source_index = evt.source_index;

	evt.target.damage(dmg, -1.0, evt.direction);
}

void EnergyDamage(Event& evt, double Amount) {
	DamageEvent dmg;
	dmg.damage = Amount * double(evt.efficiency) * double(evt.partiality);
	dmg.partiality = evt.partiality;
	dmg.impact = evt.impact;

	@dmg.obj = evt.obj;
	@dmg.target = evt.target;
	dmg.source_index = evt.source_index;
	dmg.flags |= DT_Energy | DF_FullDR | ReachedInternals;

	evt.target.damage(dmg, -1.0, evt.direction);
	
	//if(dmg.flags & ReachedInternals != 0 && evt.target.isShip)
	//	cast<Ship>(evt.target).startFire();
}

void ExplDamage(Event& evt, double Amount) {
	DamageEvent dmg;
	dmg.damage = Amount * double(evt.efficiency) * double(evt.partiality);
	dmg.partiality = evt.partiality;
	dmg.impact = evt.impact;

	@dmg.obj = evt.obj;
	@dmg.target = evt.target;
	dmg.source_index = evt.source_index;
	dmg.flags |= DT_Explosive | ReachedInternals;

	evt.target.damage(dmg, -1.0, evt.direction);
	
	//if(dmg.flags & ReachedInternals != 0 && evt.target.isShip)
	//	cast<Ship>(evt.target).mangle(Amount);
}

void SelfDestruct(Event& evt, double Amount, double Radius, double Hits) {
	if(evt.obj.inCombat)
		AreaExplDamage(evt, Amount, Radius, Hits, 0);
}

void AreaExplDamage(Event& evt, double Amount, double Radius, double Hits) {
	AreaExplDamage(evt, Amount, Radius, Hits, 0);
}

void AreaExplDamage(Event& evt, double Amount, double Radius, double Hits, double Spillable) {
	Object@ targ = evt.target !is null ? evt.target : evt.obj;

	vec3d center = targ.position + evt.impact.normalize(targ.radius);
	array<Object@>@ objs = findInBox(center - vec3d(Radius), center + vec3d(Radius), evt.obj.owner.hostileMask);

	playParticleSystem("TorpExplosionRed", center, quaterniond(), Radius / 3.0, targ.visibleMask);

	uint hits = round(Hits);
	double maxDSq = Radius * Radius;
	
	for(uint i = 0, cnt = objs.length; i < cnt; ++i) {
		Object@ target = objs[i];
		vec3d off = target.position - center;
		double dist = off.length - target.radius;
		if(dist > Radius)
			continue;
		
		double deal = Amount;
		if(dist > 0.0)
			deal *= 1.0 - (dist / Radius);
		
		//Rock the boat
		if(target.hasMover) {
			double amplitude = deal * 0.2 / (target.radius * target.radius);
			target.impulse(off.normalize(min(amplitude,8.0)));
			target.rotate(quaterniond_fromAxisAngle(off.cross(off.cross(target.rotation * vec3d_front())).normalize(), (randomi(0,1) == 0 ? 1.0 : -1.0) * atan(amplitude * 0.2) * 2.0));
		}
		
		DamageEvent dmg;
		@dmg.obj = evt.obj;
		@dmg.target = target;
		dmg.source_index = evt.source_index;
		dmg.flags |= DT_Projectile;
		dmg.impact = off.normalized(target.radius);
		dmg.spillable = Spillable != 0;
		
		vec2d dir = vec2d(off.x, off.z).normalized();

		for(uint n = 0; n < hits; ++n) {
			dmg.partiality = evt.partiality / double(hits);
			dmg.damage = deal * double(evt.efficiency) * double(dmg.partiality);

			target.damage(dmg, -1.0, dir);
		}
	}
}

void ProjDamage(Event& evt, double Amount, double Pierce, double Suppression) {
	ProjDamage(evt, Amount, Pierce, Suppression, 0);
}

void ProjDamage(Event& evt, double Amount, double Pierce, double Suppression, double IgnoreDR) {
	DamageEvent dmg;
	dmg.damage = Amount * double(evt.efficiency) * double(evt.partiality);
	dmg.partiality = evt.partiality;
	dmg.pierce = Pierce;
	dmg.impact = evt.impact;

	@dmg.obj = evt.obj;
	@dmg.target = evt.target;
	dmg.source_index = evt.source_index;
	dmg.flags |= DT_Projectile;

	if(IgnoreDR != 0)
		dmg.flags |= DF_IgnoreDR;

	evt.target.damage(dmg, -1.0, evt.direction);
	
	if(Suppression > 0 && evt.target.isShip) {
		double r = evt.target.radius;
		double suppress = Suppression * double(evt.efficiency) * double(evt.partiality) / (r*r*r);
		cast<Ship>(evt.target).suppress(suppress);
	}
}

void ProjImpact(Event& evt, double Amount, double Pierce, double IgnoreDR, double Impulse) {
	DamageEvent dmg;
	dmg.damage = Amount * double(evt.efficiency) * double(evt.partiality);
	dmg.partiality = evt.partiality;
	dmg.pierce = Pierce;
	dmg.impact = evt.impact;

	@dmg.obj = evt.obj;
	@dmg.target = evt.target;
	dmg.source_index = evt.source_index;
	dmg.flags |= DT_Projectile;

	if(IgnoreDR != 0)
		dmg.flags |= DF_IgnoreDR;

	evt.target.damage(dmg, -1.0, evt.direction);

	if(Impulse != 0) {
		Ship@ ship = cast<Ship>(evt.target);
		if(ship !is null)
			ship.impulse((ship.position - evt.obj.position).normalize(Impulse / ship.getMass()));
	}
}

void BombardDamage(Event& evt, double Amount) {
	Planet@ planet = cast<Planet>(evt.target);
	if(planet !is null)
		planet.removePopulation(Amount);
}

void SurfaceBombard(Event& evt, double Duration, double Stacks) {
	int stacks = int(Stacks);
	Planet@ planet = cast<Planet>(evt.target);
	if(planet !is null) {
		Duration /= double(planet.level) * 0.5 + 1.0;
		int status = getStatusID("Devastation");
		for(int i = 0; i < stacks; ++i)
			planet.addStatus(status, Duration);
	}
}

bool WeaponFire(const Effector& efftr, Object& obj, Object& target, float& efficiency, double supply) {
	Ship@ ship = cast<Ship>(obj);
	if(ship is null)
		return true;

	ship.consumeSupply(supply);
	return true;
}

bool RequiresSupply(const Effector& efftr, Object& obj, Object& target, float& efficiency, double supply) {
	Ship@ ship = cast<Ship>(obj);
	if(ship is null)
		return true;

	return ship.consumeMinSupply(supply);
}

DamageEventStatus CapDamage(DamageEvent& evt, const vec2u& position,
	double maxDamage, double MinimumPercent)
{
	if(evt.flags & DF_IgnoreDR != 0)
		return DE_Continue;
	if(evt.flags & DF_FullDR != 0)
		MinimumPercent = 0.01;
	if(evt.damage > maxDamage * evt.partiality)
		evt.damage = max(maxDamage * evt.partiality, evt.damage * MinimumPercent);
	return DE_Continue;
}

DamageEventStatus ReduceDamage(DamageEvent& evt, const vec2u& position,
	double ProjResist, double EnergyResist, double ExplResist, double MinPct)
{
	if(evt.flags & DF_IgnoreDR != 0)
		return DE_Continue;
	if(evt.flags & DF_FullDR != 0)
		MinPct = 0.01;

	//Prevent internal-only effects
	evt.flags &= ~ReachedInternals;

	double dmg = evt.damage;
	double dr;
	switch(evt.flags & typeMask) {
		case DT_Projectile:
			dr = ProjResist; break;
		case DT_Energy:
			dr = EnergyResist; break;
		case DT_Explosive:
			dr = ExplResist; break;
		case DT_Generic:
		default:
			dr = (ProjResist + EnergyResist + ExplResist) / 3.0; break;
	}
	
	dmg -= dr * evt.partiality;
	double minDmg = evt.damage * MinPct;
	if(dmg < minDmg)
		dmg = minDmg;
	evt.damage = dmg;
	return DE_Continue;
}

DamageEventStatus DamageResist(DamageEvent& evt, const vec2u& position, double Amount, double MinPct)
{
	if(evt.flags & DF_IgnoreDR != 0)
		return DE_Continue;
	if(evt.flags & DF_FullDR != 0)
		MinPct = 0.01;

	//Prevent internal-only effects
	evt.flags &= ~ReachedInternals;

	double dmg = evt.damage - (Amount * evt.partiality);
	double minDmg = evt.damage * MinPct;
	if(dmg < minDmg)
		dmg = minDmg;
	evt.damage = dmg;
	return DE_Continue;
}

DamageEventStatus DamageDistributeHealth(DamageEvent& evt, const vec2u& position)
{
	evt.blueprint.damage(evt.target, evt, position);
	distributeHealth(evt.blueprint, evt.target, position);
	return DE_SkipHex;
}

void DistributeHealth(Event& evt) {
	const Subsystem@ sys = evt.source;
	if(sys is null)
		return;
	for(uint n = 0, cnt = ceil(evt.time * 4.0); n < cnt; ++n) {
		vec2u hex = sys.hexagon(randomi(0, sys.hexCount-1));
		distributeHealth(evt.blueprint, evt.obj, hex);
	}
}

//This is ugly as shit to prevent allocation. Macros would've been nice but ah well.
void distributeHealth(Blueprint& bp, Object& obj, const vec2u& position) {
	auto@ curSys = bp.design.subsystem(position);
	if(curSys is null)
		return;

	double totHealth = 0;
	double totMax = 0;
	uint hexes = 1;
	bool offset = (position.x % 2) != 0;

	//Collect health variables for all nearby hexes
	vec2u pos = position;
	double h0 = bp.design.variable(pos, HV_HP);
	totMax += h0;
	HexStatus@ stat0 = bp.getHexStatus(pos.x, pos.y);
	totHealth += h0 * double(stat0.hp) / 255.0;
	bp.quadrantHP(bp.design.getQuadrant(pos)) -= h0 * double(stat0.hp) / 255.0;

	double h1 = 0;
	HexStatus@ stat1;
	vec2u pos1 = position; pos1.y -= 1;
	if(bp.design.subsystem(pos1) is curSys) {
		h1 = bp.design.variable(pos1, HV_HP);
		totMax += h1;
		@stat1 = bp.getHexStatus(pos1.x, pos1.y);

		double mod = h1 * double(stat1.hp) / 255.0;
		totHealth += mod;
		bp.quadrantHP(bp.design.getQuadrant(pos1)) -= mod;

		hexes += 1;
	}

	double h2 = 0;
	HexStatus@ stat2;
	vec2u pos2 = position; pos2.x -= 1; if(!offset) pos2.y -= 1;
	if(bp.design.subsystem(pos2) is curSys) {
		h2 = bp.design.variable(pos2, HV_HP);
		totMax += h2;
		@stat2 = bp.getHexStatus(pos2.x, pos2.y);

		double mod = h2 * double(stat2.hp) / 255.0;
		totHealth += mod;
		bp.quadrantHP(bp.design.getQuadrant(pos2)) -= mod;

		hexes += 1;
	}

	double h3 = 0;
	HexStatus@ stat3;
	vec2u pos3 = position; pos3.x += 1; if(!offset) pos3.y -= 1;
	if(bp.design.subsystem(pos3) is curSys) {
		h3 = bp.design.variable(pos3, HV_HP);
		totMax += h3;
		@stat3 = bp.getHexStatus(pos3.x, pos3.y);

		double mod = h3 * double(stat3.hp) / 255.0;
		totHealth += mod;
		bp.quadrantHP(bp.design.getQuadrant(pos3)) -= mod;

		hexes += 1;
	}

	double h4 = 0;
	HexStatus@ stat4;
	vec2u pos4 = position; pos4.x -= 1; if(offset) pos4.y += 1;
	if(bp.design.subsystem(pos4) is curSys) {
		h4 = bp.design.variable(pos4, HV_HP);
		totMax += h4;
		@stat4 = bp.getHexStatus(pos4.x, pos4.y);

		double mod = h4 * double(stat4.hp) / 255.0;
		totHealth += mod;
		bp.quadrantHP(bp.design.getQuadrant(pos4)) -= mod;

		hexes += 1;
	}

	double h5 = 0;
	HexStatus@ stat5;
	vec2u pos5 = position; pos5.y += 1;
	if(bp.design.subsystem(pos5) is curSys) {
		h5 = bp.design.variable(pos5, HV_HP);
		totMax += h5;
		@stat5 = bp.getHexStatus(pos5.x, pos5.y);

		double mod = h5 * double(stat5.hp) / 255.0;
		totHealth += mod;
		bp.quadrantHP(bp.design.getQuadrant(pos5)) -= mod;

		hexes += 1;
	}

	double h6 = 0;
	HexStatus@ stat6;
	vec2u pos6 = position; pos6.x += 1; if(offset) pos6.y += 1;
	if(bp.design.subsystem(pos6) is curSys) {
		h6 = bp.design.variable(pos6, HV_HP);
		totMax += h6;
		@stat6 = bp.getHexStatus(pos6.x, pos6.y);

		double mod = h6 * double(stat6.hp) / 255.0;
		totHealth += mod;
		bp.quadrantHP(bp.design.getQuadrant(pos6)) -= mod;

		hexes += 1;
	}

	//Set all hexes to the same health value
	double targPct = totHealth / totMax;
	uint targTake = ceil(targPct * 255);
	uint take;

	{
		take = min(targTake, uint(floor(totHealth / h0 * 255.0)));
		stat0.hp = take;
		bp.quadrantHP(bp.design.getQuadrant(pos)) += h0 * double(stat0.hp) / 255.0;
		totHealth -= stat0.hp * h0 / 255.0;
	}

	if(stat1 !is null) {
		take = min(targTake, uint(floor(totHealth / h1 * 255.0)));
		stat1.hp = take;
		bp.quadrantHP(bp.design.getQuadrant(pos1)) += h1 * double(stat1.hp) / 255.0;
		totHealth -= stat1.hp * h1 / 255.0;
	}

	if(stat2 !is null) {
		take = min(targTake, uint(floor(totHealth / h2 * 255.0)));
		stat2.hp = take;
		bp.quadrantHP(bp.design.getQuadrant(pos2)) += h2 * double(stat2.hp) / 255.0;
		totHealth -= stat2.hp * h2 / 255.0;
	}

	if(stat3 !is null) {
		take = min(targTake, uint(floor(totHealth / h3 * 255.0)));
		stat3.hp = take;
		bp.quadrantHP(bp.design.getQuadrant(pos3)) += h3 * double(stat3.hp) / 255.0;
		totHealth -= stat3.hp * h3 / 255.0;
	}

	if(stat4 !is null) {
		take = min(targTake, uint(floor(totHealth / h4 * 255.0)));
		stat4.hp = take;
		bp.quadrantHP(bp.design.getQuadrant(pos4)) += h4 * double(stat4.hp) / 255.0;
		totHealth -= stat4.hp * h4 / 255.0;
	}

	if(stat5 !is null) {
		take = min(targTake, uint(floor(totHealth / h5 * 255.0)));
		stat5.hp = take;
		bp.quadrantHP(bp.design.getQuadrant(pos5)) += h5 * double(stat5.hp) / 255.0;
		totHealth -= stat5.hp * h5 / 255.0;
	}

	if(stat6 !is null) {
		take = min(targTake, uint(floor(totHealth / h6 * 255.0)));
		stat6.hp = take;
		bp.quadrantHP(bp.design.getQuadrant(pos6)) += h6 * double(stat6.hp) / 255.0;
		totHealth -= stat6.hp * h6 / 255.0;
	}

	if(totHealth > 0.001)
		bp.currentHP -= totHealth;
}

DamageEventStatus ShieldDamage(DamageEvent& evt, vec2u& position, vec2d& direction) {
	Ship@ ship = cast<Ship>(evt.target);
	if(ship !is null && ship.Shield > 0) {
		double maxShield = ship.MaxShield;
		if(maxShield <= 0.0)
			maxShield = ship.Shield;
	
		double dmgScale = (evt.damage * ship.Shield) / (maxShield * maxShield);
		if(dmgScale < 0.01) {
			//TODO: Simulate this effect on the client
			if(randomd() < dmgScale / 0.001)
				playParticleSystem("ShieldImpactLight", ship.position + evt.impact.normalized(ship.radius * 0.9), quaterniond_fromVecToVec(vec3d_front(), evt.impact), ship.radius, ship.visibleMask, networked=false);
		}
		else if(dmgScale < 0.05) {
			playParticleSystem("ShieldImpactMedium", ship.position + evt.impact.normalized(ship.radius * 0.9), quaterniond_fromVecToVec(vec3d_front(), evt.impact), ship.radius, ship.visibleMask);
		}
		else {
			playParticleSystem("ShieldImpactHeavy", ship.position + evt.impact.normalized(ship.radius * 0.9), quaterniond_fromVecToVec(vec3d_front(), evt.impact), ship.radius, ship.visibleMask, networked=false);
		}
		
		double block;
		if(ship.MaxShield > 0)
			block = min(ship.Shield * min(ship.Shield / maxShield, 1.0), evt.damage);
		else
			block = min(ship.Shield, evt.damage);
		
		ship.Shield -= block;
		evt.damage -= block;

		if(evt.damage <= 0.0)
			return DE_EndDamage;
	}
	return DE_Continue;
}

DamageEventStatus ShieldBlock(DamageEvent& evt, vec2u& position, vec2d& direction, double Chance) {
	Ship@ ship = cast<Ship>(evt.target);

	//The lower the shield strength, the lower the chance
	if(ship !is null) {
		double maxShield = ship.MaxShield;
		double shield = ship.Shield;
		if(maxShield <= 0.0001 || shield <= 0.0001)
			return DE_Continue;
		Chance *= (shield / maxShield);
	}
	
	//The more damaged the hardener, the lower the chance
	Chance *= double(evt.destination_status.workingHexes) / double(evt.destination.hexCount);

	//Deal with partiality in the chance
	if(evt.partiality != 1.0)
		Chance = pow(Chance, 1.0 / double(evt.partiality));

	//Fully block hits with a particular chance
	if(Chance > 0.001 && randomd() < Chance) {
		evt.damage = 0.0;
		return DE_EndDamage;
	}
	return DE_Continue;
}
