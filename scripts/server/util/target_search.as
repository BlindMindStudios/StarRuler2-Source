import abilities;

export findEnemy, doesAutoTarget;
export findAlliedFleet;
export findCastable;

Object@ findEnemy(Object@ origin, Object@ obj, Empire@ emp, const vec3d& around, double area = -1.0, int depth = 3, bool ignoreSecondary = false) {
	double areaSQ = area * area;
	if(obj is origin && origin.isShip) {
		Ship@ ship = cast<Ship>(origin);
		Object@ targ = ship.blueprint.getCombatTarget();
		if(targ is null)
			@targ = ship.getLastHitBy();
		if(targ !is null) {
			if(targ.isVisibleTo(emp)) {
				if(ignoreSecondary) {
					if(targ.isShip && targ.hasSupportAI)
						@targ = cast<Ship>(targ).Leader;
				}
				if(targ !is null) {
					if((!ignoreSecondary || (!targ.isPlanet && !targ.isColonyShip && !targ.isCivilian && targ.owner !is null && (targ.owner.major || !emp.major)))
						&& doesAutoTarget(origin, targ)) {
						if(area < 0 || targ.position.distanceToSQ(around) < areaSQ)
							return targ;
					}
				}
			}
		}
	}
	for(int i = 0; i < TARGET_COUNT; ++i) {
		Object@ targ = obj.targets[i];
		if(targ.isVisibleTo(emp)) {
			if(ignoreSecondary) {
				if(targ.isShip && targ.hasSupportAI)
					@targ = cast<Ship>(targ).Leader;
				if(targ is null)
					continue;
			}
			if((!ignoreSecondary || (!targ.isPlanet && !targ.isColonyShip && !targ.isCivilian && targ.owner !is null && (targ.owner.major || !emp.major)))
				&& doesAutoTarget(origin, targ)) {
				if(area < 0 || targ.position.distanceToSQ(around) < areaSQ)
					return targ;
			}
		}
		if(depth > 1) {
			@targ = findEnemy(origin, targ, emp, around, area, depth - 1, ignoreSecondary);
			if(targ !is null)
				return targ;
		}
	}
	return null;
}

bool doesAutoTarget(Object@ from, Object@ to) {
	Ship@ ship = cast<Ship>(from);
	if(ship !is null) {
		if(!ship.blueprint.canTarget(from, to))
			return false;
		return ship.blueprint.doesAutoTarget(from, to);
	}
	if(to.notDamageable)
		return false;
	return from.owner.isHostile(to.owner) && (to.isShip || to.isOrbital);
}

Object@ findAlliedFleet(Object@ obj, Empire@ emp, const vec3d& around, double area = -1.0, int depth = 3) {
	double areaSQ = area * area;
	for(int i = 0; i < TARGET_COUNT; ++i) {
		Object@ targ = obj.targets[i];
		if(targ.owner is emp) {
			if(targ.isShip && targ.hasSupportAI)
				@targ = cast<Ship>(targ).Leader;
			if(targ.isShip && targ.hasLeaderAI) {
				if(area < 0 || targ.position.distanceToSQ(around) < areaSQ)
					return targ;
			}
		}
		if(depth > 1) {
			@targ = findAlliedFleet(targ, emp, around, area, depth - 1);
			if(targ !is null)
				return targ;
		}
	}
	return null;
}

ThreadLocal<Targets@> locTargs;
Object@ findCastable(Ability@ abl, Object@ obj = null, int depth = 3, double range = 0.0, Targets@ targs = null) {
	if(obj is null)
		@obj = abl.obj;
	if(obj is null)
		return null;
	if(range == 0.0)
		range = abl.getRange();
	if(targs is null) {
		Targets wtf(abl.targets);
		@targs = wtf;
		if(targs.length == 0)
			return null;
		targs[0].filled = true;
	}
	double areaSQ = range * range;
	for(int i = 0; i < TARGET_COUNT; ++i) {
		Object@ targ = obj.targets[i];
		if(targ.position.distanceToSQ(obj.position) <= areaSQ) {
			@targs[0].obj = targ;
			if(abl.canActivate(targs))
				return targ;
			if(targ.isShip && targ.hasSupportAI) {
				@targs[0].obj = cast<Ship>(targ).Leader;
				if(targs[0].obj !is null && abl.canActivate(targs))
					return targs[0].obj;
			}
		}
		if(depth > 1) {
			@targ = findCastable(abl, obj, depth - 1, range, targs);
			if(targ !is null)
				return targ;
		}
	}
	return null;
}
