import saving;
import design_settings;

//Time needed for a support ship to expire if left without a leader
const double SUPPORT_EXPIRE_TIME = 3.0 * 60.0;

//Max distance a support ship can find a leader to attach to
const double MAX_LEADER_RESCUE_DIST = 1000.0;
const double MAX_LEADER_RESCUE_DIST_SQ = MAX_LEADER_RESCUE_DIST * MAX_LEADER_RESCUE_DIST;
const double MAX_SUPPORT_ABANDON_DIST = 2500.0;
const double MAX_SUPPORT_ABANDON_DIST_SQ = MAX_SUPPORT_ABANDON_DIST * MAX_SUPPORT_ABANDON_DIST;

enum SupportOrder {
	SO_Idle,
	SO_Attack,
	SO_Interfere,
	SO_Retreat,
	SO_Raid,
	SO_AttackBlind
};

tidy class SupportAI : Component_SupportAI, Savable {
	double expire_progress = 0;
	bool findLeader = true;
	bool leaderDelta = false;
	vec3d newOffset;

	Object@ leader;
	int leaderId = 0;
	
	float psr = randomf(0.f,1.f);
	float returnTimer = 0.f;

	uint range = SR_Auto;
	bool detached = false, freeToRaid = true;

	double engageRange = -1.0;
	SupportOrder order = SO_Idle;
	uint goal = SG_Cannon;
	Object@ target, relTarget, checkTarget;

	SupportAI() {
	}

	void load(SaveFile& msg) {
		msg >> expire_progress;
		msg >> findLeader;
		msg >> newOffset;
		if(msg < SV_0054) {
			order = SO_Attack; //The ship will automatically reset to the correct state
			engageRange = 75.0;
		}
		else {
			uint o = SO_Idle;
			msg >> o;
			order = SupportOrder(o);
			msg >> target >> relTarget;
			msg >> engageRange;
			if(msg < SV_0068 && engageRange < 0.0)
				engageRange = 75.0;
		}
		if(msg >= SV_0120) {
			msg >> goal;
			msg >> range;
			msg >> detached;
		}
		else if(range == SR_Auto) {
			range = SR_Far;
		}
		if(msg >= SV_0138)
			msg >> leaderId;
	}

	void supportPostLoad(Object& obj) {
		if(obj.isShip)
			@leader = cast<Ship>(obj).Leader;
	}

	void save(SaveFile& msg) {
		msg << expire_progress;
		msg << findLeader;
		msg << newOffset;
		msg << uint(order);
		msg << target << relTarget;
		msg << engageRange;
		msg << goal;
		msg << range;
		msg << detached;
		msg << leaderId;
	}

	int get_LeaderID() {
		return leaderId;
	}
	
	void supportIdle(Object& obj) {
		obj.leaderLock = true;
		order = SO_Idle;
		@target = null;
		@relTarget = null;
	}

	void supportIdle(Object& obj, bool immediate) {
		if(detached && !immediate)
			returnTimer = 6.f;
		else
			obj.leaderLock = true;
		order = SO_Idle;
		@target = null;
		@relTarget = null;
	}
	
	void supportAttack(Object& obj, Object@ targ) {
		auto@ ship = cast<Ship>(obj);
		//Ignore attack orders if there are no weapons
		if(engageRange <= 0 || ship.DPS <= 1.0e-4)
			return;
		switch(goal) {
			case SG_Brawler: //Raid supports
				freeToRaid = true;
			case SG_Cavalry:
				if(ship.MaxSupply > 1.0e-4 || (leader !is null && leader.freeRaiding))
					order = SO_Raid;
				else
					order = SO_Attack;
				break;
			case SG_Artillery:
				order = SO_Attack;
				break;
			case SG_Cannon:
				if(leader !is null && leader.freeRaiding) {
					order = SO_Raid;
					freeToRaid = true;
				}
				else
					order = SO_AttackBlind;
				break;
			case SG_Satellite:
				break;
			default:
				return;
		}
		
		if(obj.isShip) {
			Ship@ ship = cast<Ship>(obj);
			if(targ !is null)
				ship.blueprint.target(obj, targ, TF_Preference);
		}
		@target = targ;
		@relTarget = null;
	}
	
	void supportInterfere(Object& obj, Object@ targ, Object@ protect) {
		if(goal == SG_Shield) {
			order = SO_Interfere;
			@target = targ;
			@relTarget = protect;
		}
	}
	
	void cavalryCharge(Object& obj, Object@ targ) {
		if(goal == SG_Cavalry) {
			freeToRaid = true;
			supportAttack(obj, targ);
		}
		else {
			@checkTarget = targ;
		}
	}
	
	void set_doRaids(bool raid) {
		freeToRaid = raid;
	}

	bool get_isDetached(Object& obj) {
		return detached;
	}

	bool get_isRaiding() {
		return detached || order == SO_Raid;
	}

	void resupplyFromFleet(Object& obj) {
		Ship@ ship = cast<Ship>(obj);
		Ship@ leaderShip = cast<Ship>(leader);
		if(ship.Supply < ship.MaxSupply) {
			if(leaderShip is null)
				return;
			double require = ship.MaxSupply - ship.Supply;
			if(leaderShip.Supply < require)
				return;
			leaderShip.consumeSupply(require);
			ship.Supply = min(ship.MaxSupply, ship.Supply + require);
		}
	}

	void dumpSupplyToFleet(Object& obj) {
		Ship@ ship = cast<Ship>(obj);
		Ship@ leaderShip = cast<Ship>(leader);
		if(ship.Supply >= 0.001) {
			if(leaderShip is null)
				return;
			leaderShip.refundSupply(ship.Supply);
			ship.Supply = 0;
		}
	}
	
	void supportRetreat(Object& obj) {
		order = SO_Retreat;
		@target = null;
		@relTarget = null;
	}
	
	void set_supportEngageRange(double range) {
		engageRange = range;
	}

	void preventExpire() {
		expire_progress = -FLOAT_INFINITY;
	}

	void supportInit(Object& obj) {
		Ship@ ship = cast<Ship>(obj);
		const Design@ dsg = ship.blueprint.design;
		auto@ settings = cast<const DesignSettings>(dsg.settings);
		if(settings !is null) {
			if(dsg.hasTag(ST_Satellite))
				goal = SG_Satellite;
			else
				goal = settings.behavior;
			range = settings.range;
		}
		//TODO: Properly resolve auto range here?
		if(range == SR_Auto)
			range = SR_Far;
	}

	//Complete a leader change received from the leader
	void completeRegisterLeader(Object& obj, Object@ newLeader) {
		Ship@ ship = cast<Ship>(obj);
		Object@ prevLeader = leader;
		if(prevLeader !is null)
			prevLeader.unregisterSupport(obj, false);
		@ship.Leader = newLeader;
		if(newLeader !is null) {
			leaderId = newLeader.id;
			@leader = newLeader;
		}
		else {
			leaderId = 0;
			@leader = null;
		}
		if(newOffset.lengthSQ > 0.0001)
			obj.setFleetOffset(newOffset);
		ship.triggerLeaderChange(prevLeader, newLeader);
		leaderDelta = true;
	}

	void clearLeader(Object& obj, Object@ prevLeader) {
		Ship@ ship = cast<Ship>(obj);
		if(leader is prevLeader) {
			@ship.Leader = null;
			@leader = null;
			leaderId = 0;
			ship.triggerLeaderChange(prevLeader, null);
		}
	}

	void transferTo(Object& obj, Object@ newLeader) {
		newOffset = vec3d();
		newLeader.registerSupport(obj);

		Ship@ ship = cast<Ship>(obj);
		if(ship !is null && ship.isFree)
			ship.makeNotFree();
	}

	void transferTo(Object& obj, Object@ newLeader, vec3d offset) {
		newOffset = offset;
		newLeader.registerSupport(obj);

		Ship@ ship = cast<Ship>(obj);
		if(ship !is null && ship.isFree)
			ship.makeNotFree();
	}

	void setFleetOffset(Object& obj, vec3d offset) {
		Ship@ ship = cast<Ship>(obj);
		double fradius = leader.getFormationRadius();
		if(offset.length > fradius)
			return;
		ship.formationDest.xyz = offset;
		newOffset = offset;
		leaderDelta = true;
	}

	void supportDestroy(Object& obj) {
		Ship@ ship = cast<Ship>(obj);
		if(leader !is null) {
			auto@ prevLeader = leader;
			leader.unregisterSupport(obj, true);
			@ship.Leader = null;
			@leader = null;
			leaderId = 0;
			ship.triggerLeaderChange(prevLeader, null);
		}
		@target = null;
		@relTarget = null;
	}

	void supportScuttle(Object& obj) {
		Ship@ ship = cast<Ship>(obj);
		Object@ prevLeader = leader;
		if(prevLeader !is null)
			prevLeader.unregisterSupport(obj, false);
		findLeader = false;
		@ship.Leader = null;
		@leader = null;
		leaderId = 0;
		ship.triggerLeaderChange(prevLeader, null);
		obj.destroy();
		leaderDelta = true;
	}

	Object@ findNearbyLeader(Object& obj, Object& findFrom, uint depth, int size) {
		--depth;

		vec3d pos = obj.position;
		for(uint i = 0; i < TARGET_COUNT; ++i) {
			Object@ other = findFrom.targets[i];
			if(other.owner is obj.owner) {
				Object@ check = other;
				if(check.isShip && check.hasSupportAI && check.LeaderID != 0)
					@check = cast<Ship>(check).Leader;
				if(check !is null && check.hasLeaderAI) {
					if(pos.distanceToSQ(check.position) < MAX_LEADER_RESCUE_DIST_SQ && check.canTakeSupport(size, pickup=true))
						return check;
				}
			}

			if(depth != 0) {
				@other = findNearbyLeader(obj, other, depth, size);
				if(other !is null)
					return other;
			}
		}

		return null;
	}
	
	double evaluateTarget(Object& obj, Object& targ, double maxDistSQ) {
		Ship@ ship = cast<Ship>(targ);
		if(ship is null || !obj.owner.isHostile(targ.owner))
			return 0;
		if(targ.position.distanceToSQ(leader.position) > maxDistSQ)
			return 0;
		
		switch(goal) {
			case SG_Brawler:
				return (1.0 + ship.DPS) * (ship.hasSupportAI ? 1.0 : 0.001);
			case SG_Shield:
				return (1.0 + ship.DPS);
			case SG_Cavalry:
				return (1.0 + ship.DPS) * (ship.hasSupportAI ? 1.0 : 0.001);
			case SG_Artillery:
				return (1.0 + ship.DPS) * (ship.hasSupportAI ? 1.0 : 0.001);
			case SG_Cannon:
				return ship.hasSupportAI ? 1.0 : 0.001;
			case SG_Support:
				return 1.0;
			default:
				return 1.0;
		}
		
		return 0;
	}

	uint targCycle = 0;
	Object@ replaceTarget(Object& obj, Object& prev, double maxDistSQ) {
		Object@ targ = obj.targets[++targCycle % 3];
		double b = evaluateTarget(obj, targ, maxDistSQ);
		if(b <= 0)
			return prev;
		
		double a = evaluateTarget(obj, prev, maxDistSQ);
		
		if(a >= b * 0.9)
			return prev;
		else
			return targ;
	}
	
	void supportTick(Object& obj, double time) {
		Ship@ ship = cast<Ship>(obj);

		double abandonDist = MAX_SUPPORT_ABANDON_DIST_SQ;
		double raidDist = 0;
		if(leader !is null) {
			raidDist = leader.raidRange;
			if(raidDist < 0) {
				Region@ reg = obj.region;
				if(reg !is null) {
					abandonDist = max(abandonDist, sqr(reg.radius));
					raidDist = reg.radius;
				}
				else
					raidDist = 0;
			}
			else {
				abandonDist = max(abandonDist, sqr(raidDist * 1.5));
			}
		}

		//Tick forward the expiration
		if(leader is null) {
			detached = true;
			if(ship.velocity.lengthSQ > 0.01)
				ship.stopMoving(false);
			expire_progress += time;
			if(expire_progress > SUPPORT_EXPIRE_TIME + (double(uint8(obj.id)) / 128.0) - 1.0) {
				obj.destroy();
				return;
			}
		}
		else if(expire_progress > time) {
			expire_progress -= time;
		}
		else {
			expire_progress = 0;
		}

		if(leader !is null) {
			if(leader.owner !is obj.owner
				|| (ship.position.distanceToSQ(leader.position) > abandonDist
						&& (ship.region is null || ship.region !is leader.region)
						&& !ship.isFTLing && (!leader.isShip || !cast<Ship>(leader).isFTLing))
						&& (!detached || order == SO_Idle) && !obj.inCombat) {
				//We tell the leader we died, as we are being abandoned and will probably die
				leader.unregisterSupport(obj, true);
				auto@ prevLeader = leader;
				@ship.Leader = null;
				@leader = null;
				leaderId = 0;
				ship.triggerLeaderChange(prevLeader, null);
			}
			else {
				double fleetRad = leader.getFormationRadius();
				double engageDist = engageRange + fleetRad;
				{
					//If the target is out of range, return to the fleet
					bool wasDetached = detached;
					detached = leader.position.distanceToSQ(obj.position) > fleetRad * fleetRad * 1.05;
					if(detached && !wasDetached)
						resupplyFromFleet(obj);
				}
				
				switch(order) {
					case SO_Idle:
						if(!detached && ship.Supply > 1.0e-4)
							dumpSupplyToFleet(obj);
					
						switch(goal) {
							case SG_Shield: {
								Object@ targ = ship.blueprint.getCombatTarget();
								double quality = 0;
								for(uint i = 0; i < TARGET_COUNT; ++i) {
									Object@ t = obj.targets[i];
									if(obj.owner.isHostile(t.owner) && (t.isShip || t.isOrbital)) {
										double q = evaluateTarget(obj, t, INFINITY);
										if(q > quality) {
											@targ = t;
											quality = q;
										}
										break;
									}
								}
								
								if(targ !is null)
									supportInterfere(obj, leader, targ);
								}
								break;
							case SG_Support:
							case SG_Cavalry:
								break;
							default: {
								Object@ targ = ship.blueprint.getCombatTarget();
								double quality = 0;
								double maxDist = max(raidDist*raidDist, engageDist*engageDist);
								for(uint i = 0; i < TARGET_COUNT; ++i) {
									Object@ t = obj.targets[i];
									if(obj.owner.isHostile(t.owner) && (t.isShip || t.isOrbital)) {
										double q = evaluateTarget(obj, t, maxDist);
										if(q > quality) {
											@targ = t;
											quality = q;
										}
										break;
									}
								}
								if(checkTarget !is null) {
									double q = evaluateTarget(obj, checkTarget, maxDist);
									if(q > quality) {
										@targ = checkTarget;
										quality = q;
									}
									@checkTarget = null;
								}
								
								if(targ !is null && obj.owner.isHostile(targ.owner))
									supportAttack(obj, targ);
							}
						}

						if(order == SO_Idle) {
							if(returnTimer > 0.f) {
								returnTimer -= time;
								if(returnTimer <= 0.f || !detached)
									obj.leaderLock = true;
							}
						}
						else {
							returnTimer = 0.f;
						}
						break;
					case SO_Attack:
						if(target is null || !target.valid || target.position.distanceToSQ(leader.position) > engageDist*engageDist || ship.DPS < 1.0e-4 || !obj.owner.isHostile(target.owner)) {
							supportIdle(obj);
						}
						else {
							@target = replaceTarget(obj, target, engageDist*engageDist);
						
							vec3d dest = leader.position + obj.internalDestination;
							//If the target is out of range, return to the fleet
							if(detached || leader.position.distanceToSQ(target.position) > sqr(engageRange + fleetRad)) {
								supportIdle(obj);
								break;
							}
							
							vec3d fireFrom = obj.leaderLock ? obj.position : dest;
							
							bool relocate = fireFrom.distanceToSQ(target.position) > engageRange * engageRange || fireFrom.distanceToSQ(leader.position) > fleetRad * fleetRad || obj.isColliding;
							if(!relocate) {
								if(obj.leaderLock || obj.position.distanceToSQ(dest) < obj.radius * obj.radius) {
									line3dd line = line3dd(obj.position, target.position);
									Object@ hit = trace(line, obj.owner.hostileMask | 0x1);
									if(hit !is target)
										relocate = true;
								}
							}
							
							if(relocate) {
								double innerDist = leader.radius + obj.radius;
								vec3d dest = random3d(innerDist, fleetRad);
								if((dest + leader.position).distanceToSQ(target.position) < engageRange * engageRange) {
									line3dd line = line3dd(dest + leader.position, target.position);
									Object@ hit = trace(line, obj.owner.hostileMask | 0x1);
									if(hit is target) {
										int moveId = -1;
										obj.leaderLock = false;
										returnTimer = 0.f;
										obj.moveTo(dest, moveId, doPathing=false, enterOrbit=false);
									}
								}
							}
						}
						break;
					case SO_Interfere:
						if(target is null || relTarget is null || !target.valid || !relTarget.valid || !obj.owner.isHostile(target.owner) || !obj.inCombat)
							supportIdle(obj);
						else {							
							double fleetRad = leader.getFormationRadius();
							line3dd path = line3dd(leader.position, target.position);
							double targDist = path.length;
							
							if(targDist > fleetRad * 4.0) {
								supportIdle(obj);
								break;
							}
							
							vec3d curDest = leader.position + obj.internalDestination;
							vec3d pt = path.getClosestPoint(curDest, false);
							if(obj.leaderLock || pt.distanceToSQ(curDest) > obj.radius * obj.radius) {							
								double outerDist = targDist - obj.radius * 1.5 - target.radius;
								if(outerDist > fleetRad)
									outerDist = fleetRad;
								
								double innerDist = leader.radius + obj.radius * 1.5;
								vec3d dest = path.direction * (innerDist + (outerDist - innerDist) * psr) + random3d(obj.radius * 0.5);
								int moveId = -1;
								obj.leaderLock = false;
								returnTimer = 0.f;
								obj.moveTo(dest, moveId, doPathing=false, enterOrbit=false);
							}
						}
						break;
					case SO_Raid:
						if(target is null || !target.valid || target.position.distanceToSQ(leader.position) > raidDist*raidDist || ship.DPS < 1.0e-4 || !obj.owner.isHostile(target.owner)) {
							supportIdle(obj, immediate=false);
						}
						else if(ship.Supply > 0.0 || leader.freeRaiding) {
							if(!freeToRaid)
								break;
							//TODO: Handle very low supply levels better
							@target = replaceTarget(obj, target, raidDist*raidDist);
							
							vec3d dest = leader.position + obj.internalDestination;							
							vec3d fireFrom = obj.leaderLock ? obj.position : dest;
							
							bool relocate = obj.position.distanceToSQ(dest) < obj.radius * obj.radius ||
											fireFrom.distanceToSQ(target.position) > engageRange * engageRange ||
											dest.distanceToSQ(leader.position) > abandonDist * 0.95;
							if(!relocate) {
								if(obj.leaderLock || obj.position.distanceToSQ(dest) < obj.radius * obj.radius) {
									line3dd line = line3dd(obj.position, target.position);
									Object@ hit = trace(line, obj.owner.hostileMask | 0x1);
									if(hit !is target)
										relocate = true;
								}
							}
							
							if(relocate) {
								double innerDist = target.radius + obj.radius;
								double rMax = (range == SR_Close ? engageRange * 0.52 : engageRange);
								vec3d dest = target.position + random3d(rMax * 0.9, rMax * 0.999);
								if(dest.distanceToSQ(leader.position) < abandonDist * 0.95) {
									line3dd line = line3dd(dest, target.position);
									Object@ hit = trace(line, obj.owner.hostileMask | 0x1);
									if(hit is target) {
										int moveId = -1;
										obj.leaderLock = false;
										returnTimer = 0.f;
										obj.moveTo(dest - leader.position, moveId, doPathing=false, enterOrbit=false);
									}
								}
							}
							break;
						}
						else if(detached) {
							supportIdle(obj, immediate=true);
							break;
						}
						else {
							resupplyFromFleet(obj);
						}
						break;
					case SO_AttackBlind:
						if(target is null || !target.valid || target.position.distanceToSQ(leader.position) > engageDist*engageDist || ship.DPS < 1.0e-4 || !obj.owner.isHostile(target.owner)) {
							supportIdle(obj);
						}
						else {
							@target = replaceTarget(obj, target, engageDist*engageDist);
							
							vec3d dest = leader.position + obj.internalDestination;
							double fleetRad = leader.getFormationRadius();
							//If the target is out of range, return to the fleet
							if(detached || leader.position.distanceToSQ(target.position) > sqr(engageRange + fleetRad)) {
								supportIdle(obj);
								break;
							}
							
							vec3d fireFrom = obj.leaderLock ? obj.position : dest;
							
							bool relocate = fireFrom.distanceToSQ(target.position) > engageRange * engageRange || fireFrom.distanceToSQ(leader.position) > fleetRad * fleetRad || obj.isColliding;
							if(!relocate) {
								if(obj.leaderLock || obj.position.distanceToSQ(dest) < obj.radius * obj.radius) {
									line3dd line = line3dd(obj.position, target.position);
									Object@ hit = trace(line, obj.owner.hostileMask | 0x1);
									if(hit !is null && hit !is target && !(hit.owner is target.owner && hit.type == target.type))
										relocate = true;
								}
							}
							
							if(relocate) {
								double innerDist = leader.radius + obj.radius;
								vec3d dest = random3d(innerDist, fleetRad);
								if((dest + leader.position).distanceToSQ(target.position) < engageRange * engageRange) {
									line3dd line = line3dd(dest + leader.position, target.position);
									Object@ hit = trace(line, obj.owner.hostileMask | 0x1);
									if(hit is target || hit is null || (hit.owner is target.owner && hit.type == target.type)) {
										int moveId = -1;
										obj.leaderLock = false;
										returnTimer = 0.f;
										obj.moveTo(dest, moveId, doPathing=false, enterOrbit=false);
									}
								}
							}
						}
						break;
					case SO_Retreat:
						supportIdle(obj);
						break;
				}
			}
		}
		else if(findLeader && obj.hasMover && obj.maxAcceleration > 0) {
			//Try to find a new leader
			Object@ newLeader = findNearbyLeader(obj, obj, 2, ship.blueprint.design.size);
			if(newLeader !is null)
				newLeader.registerSupport(obj, true);
		}
	}

	void writeSupportAI(const Object& obj, Message& msg) {
		const Ship@ ship = cast<const Ship>(obj);
		msg << ship.Leader;
	}

	bool writeSupportAIDelta(const Object& obj, Message& msg) {
		const Ship@ ship = cast<const Ship>(obj);
		if(leaderDelta) {
			msg.write1();
			msg << ship.Leader;
			leaderDelta = false;
			return true;
		}
		return false;
	}
};
