import regions.regions;
import saving;
import systems;
import resources;
import civilians;
import statuses;

const double ACC_SYSTEM = 2.0;
const double ACC_INTERSYSTEM = 65.0;
const int GOODS_WORTH = 8;
const double CIV_HEALTH = 25.0;
const double CIV_REPAIR = 1.0;
const double BLOCKADE_TIMER = 3.0 * 60.0;
const double DEST_RANGE = 4.0;

tidy class CivilianScript {
	uint type = 0;
	Object@ origin;
	Object@ pathTarget;
	Object@ intermediate;
	Region@ prevRegion;
	Region@ nextRegion;
	int moveId = -1;
	bool leavingRegion = false, awaitingIntermediate = false;
	bool pickedUp = false;
	double Health = CIV_HEALTH;
	int stepCount = 0;
	int income = 0;
	bool delta = false;

	uint cargoType = CT_Goods;
	const ResourceType@ cargoResource;
	int cargoWorth = 0;

	double get_health() {
		return Health;
	}

	double get_maxHealth(const Civilian& obj) {
		return CIV_HEALTH * obj.radius * obj.owner.ModHP.value;
	}

	void load(Civilian& obj, SaveFile& msg) {
		loadObjectStates(obj, msg);
		if(msg.readBit()) {
			obj.activateMover();
			msg >> cast<Savable>(obj.Mover);
		}
		msg >> type;
		msg >> origin;
		msg >> pathTarget;
		msg >> intermediate;
		msg >> prevRegion;
		msg >> nextRegion;
		msg >> moveId;
		msg >> leavingRegion;
		msg >> pickedUp;
		msg >> Health;
		msg >> stepCount;
		msg >> income;
		msg >> cargoType;
		if(msg.readBit())
			@cargoResource = getResource(msg.readIdentifier(SI_Resource));
		msg >> cargoWorth;

		makeMesh(obj);
	}

	void save(Civilian& obj, SaveFile& msg) {
		saveObjectStates(obj, msg);
		if(obj.hasMover) {
			msg.write1();
			msg << cast<Savable>(obj.Mover);
		}
		else {
			msg.write0();
		}
		msg << type;
		msg << origin;
		msg << pathTarget;
		msg << intermediate;
		msg << prevRegion;
		msg << nextRegion;
		msg << moveId;
		msg << leavingRegion;
		msg << pickedUp;
		msg << Health;
		msg << stepCount;
		msg << income;
		msg << cargoType;
		if(cargoResource is null) {
			msg.write0();
		}
		else {
			msg.write1();
			msg.writeIdentifier(SI_Resource, cargoResource.id);
		}
		msg << cargoWorth;
	}

	uint getCargoType() {
		if(cargoType == CT_Resource && !pickedUp)
			return CT_Goods;
		return cargoType;
	}

	uint getCargoResource() {
		if(cargoResource is null)
			return uint(-1);
		return cargoResource.id;
	}

	int getCargoWorth() {
		return cargoWorth;
	}

	void setCargoType(Civilian& obj, uint type) {
		cargoType = type;
		@cargoResource = null;
		if(type == CT_Goods)
			cargoWorth = GOODS_WORTH * obj.radius * CIV_RADIUS_WORTH;
		delta = true;
	}

	void setCargoResource(Civilian& obj, uint id) {
		cargoType = CT_Resource;
		@cargoResource = getResource(id);
		if(pickedUp)
			cargoWorth = cargoResource.cargoWorth * obj.radius * CIV_RADIUS_WORTH;
		else
			cargoWorth = GOODS_WORTH * obj.radius * CIV_RADIUS_WORTH;
		delta = true;
	}

	void modCargoWorth(int diff) {
		cargoWorth += diff;
		delta = true;
	}

	int getStepCount() {
		return stepCount;
	}

	void modStepCount(int mod) {
		stepCount += mod;
	}

	void resetStepCount() {
		stepCount = 0;
	}

	void init(Civilian& obj) {
		obj.sightRange = 0;
	}

	uint getCivilianType() {
		return type;
	}

	void setCivilianType(uint type) {
		this.type = type;
	}

	void modIncome(Civilian& obj, int mod) {
		if(obj.owner !is null && obj.owner.valid)
			obj.owner.modTotalBudget(+mod, MoT_Trade);
		income += mod;
	}

	void postInit(Civilian& obj) {
		if(type == CiT_Freighter && obj.owner !is null)
			obj.owner.CivilianTradeShips += 1;
		if(type == CiT_Freighter) {
			obj.activateMover();
			obj.maxAcceleration = ACC_SYSTEM;
			obj.rotationSpeed = 1.0;
		}
		makeMesh(obj);
		Health = get_maxHealth(obj);
		delta = true;
	}

	void makeMesh(Civilian& obj) {
		MeshDesc mesh;
		@mesh.model = getCivilianModel(obj.owner, type, obj.radius);
		@mesh.material = getCivilianMaterial(obj.owner, type, obj.radius);
		@mesh.iconSheet = getCivilianIcon(obj.owner, type, obj.radius).sheet;
		mesh.iconIndex = getCivilianIcon(obj.owner, type, obj.radius).index;

		bindMesh(obj, mesh);
	}

	bool onOwnerChange(Civilian& obj, Empire@ prevOwner) {
		if(income != 0 && prevOwner !is null && prevOwner.valid)
			prevOwner.modTotalBudget(-income, MoT_Trade);
		if(type == CiT_Freighter && prevOwner !is null)
			prevOwner.CivilianTradeShips -= 1;
		regionOwnerChange(obj, prevOwner);
		if(type == CiT_Freighter && obj.owner !is null)
			obj.owner.CivilianTradeShips += 1;
		if(income != 0 && prevOwner !is null && obj.owner.valid)
			obj.owner.modTotalBudget(-income, MoT_Trade);
		return false;
	}

	void destroy(Civilian& obj) {
		if((obj.inCombat || obj.engaged) && !game_ending) {
			playParticleSystem("ShipExplosion", obj.position, obj.rotation, obj.radius, obj.visibleMask);
		}
		else {
			if(cargoResource !is null) {
				for(uint i = 0, cnt = cargoResource.hooks.length; i < cnt; ++i)
					cargoResource.hooks[i].onTradeDestroy(obj, origin, pathTarget, null);
			}
		}
		if(origin !is null && origin.hasResources)
			origin.setAssignedCivilian(null);
		if(pathTarget !is null && pathTarget.isPlanet && pathTarget.owner is obj.owner) {
			auto@ status = getStatusType("Blockaded");
			if(status !is null)
				pathTarget.addStatus(status.id, timer=BLOCKADE_TIMER);
		}
		leaveRegion(obj);
		if(obj.owner !is null && obj.owner.valid) {
			if(type == CiT_Freighter)
				obj.owner.CivilianTradeShips -= 1;
			if(income != 0)
				obj.owner.modTotalBudget(-income, MoT_Trade);
		}
	}

	void freeCivilian(Civilian& obj) {
		if(origin !is null && origin.hasResources)
			origin.setAssignedCivilian(null);

		Region@ region = obj.region;
		if(region !is null) {
			@origin = null;
			@pathTarget = null;
			@prevRegion = null;
			@nextRegion = null;
			region.freeUpCivilian(obj);
		}
		else {
			@origin = null;
			@pathTarget = null;
			@prevRegion = null;
			@nextRegion = null;
			obj.destroy();
		}
	}

	float timer = 0.f;
	void occasional_tick(Civilian& obj) {
		//Update in combat flags
		bool engaged = obj.engaged;
		obj.inCombat = engaged;
		obj.engaged = false;

		if(engaged && obj.region !is null)
			obj.region.EngagedMask |= obj.owner.mask;
	}
	
	void gotoTradeStation(Civilian@ station) {
		if(!awaitingIntermediate)
			return;
		awaitingIntermediate = false;
		@intermediate = station;
	}
	
	void gotoTradePlanet(Planet@ planet) {
		if(!awaitingIntermediate)
			return;
		awaitingIntermediate = false;
		@intermediate = planet;
	}

	double tick(Civilian& obj, double time) {
		//Update normal stuff
		updateRegion(obj);
		if(obj.hasMover)
			obj.moverTick(time);

		//Tick occasional stuff
		timer -= float(time);
		if(timer <= 0.f) {
			occasional_tick(obj);
			timer = 1.f;
		}

		//Do repair
		double maxHP = get_maxHealth(obj);
		if(!obj.inCombat && Health < maxHP) {
			Health = min(Health + (CIV_REPAIR * time * obj.radius), maxHP);
			delta = true;
		}
		
		if(awaitingIntermediate)
			return 0.25;

		//Update pathing
		Region@ curRegion = obj.region;
		if(pathTarget !is null) {
			if(origin !is null && !pickedUp) {
				if(obj.moveTo(origin, moveId, distance=10.0, enterOrbit=false)) {
					pickedUp = true;
					if(cargoResource !is null)
						cargoWorth = cargoResource.cargoWorth * obj.radius * CIV_RADIUS_WORTH;
					delta = true;
					moveId = -1;
					return 0.5;
				}
				else {
					return 0.2;
				}
			}
			Region@ destRegion;
			if(pathTarget.isRegion)
				@destRegion = cast<Region>(pathTarget);
			else
				@destRegion = pathTarget.region;
			if(nextRegion is null) {
				if(curRegion is null)
					@nextRegion = findNearestRegion(obj.position);
				else
					@nextRegion = curRegion;
			}
			if(nextRegion is null || destRegion is null) {
				freeCivilian(obj);
				return 0.4;
			}
			if(leavingRegion) {
				vec3d enterDest;
				if(nextRegion !is destRegion || destRegion is pathTarget || getSystem(prevRegion).isSpatialAdjacent(getSystem(nextRegion)))  {
					enterDest = nextRegion.position + (prevRegion.position - nextRegion.position).normalized(nextRegion.radius * 0.85);
					enterDest += random3d(0.0, DEST_RANGE);
				}
				else {
					enterDest = pathTarget.position + vec3d(0,0,pathTarget.radius+10.0);
				}
				obj.maxAcceleration = ACC_INTERSYSTEM;
				if(!obj.moveTo(enterDest, moveId, enterOrbit=false))
					return 0.2;
				if(cargoType == CT_Resource)
					prevRegion.bumpTradeCounter(obj.owner);
				moveId = -1;
				leavingRegion = false;
			}
			if(curRegion is null || (nextRegion !is null && nextRegion is curRegion)) {
				if(nextRegion is destRegion) {
					//Move to destination
					obj.maxAcceleration = ACC_SYSTEM;
					if(curRegion is pathTarget || obj.moveTo(pathTarget, moveId, distance=10.0, enterOrbit=false)) {
						moveId = -1;
						if(cargoType == CT_Resource)
							destRegion.bumpTradeCounter(obj.owner);
						if(cargoResource !is null && !pathTarget.isRegion) {
							for(uint i = 0, cnt = cargoResource.hooks.length; i < cnt; ++i)
								cargoResource.hooks[i].onTradeDeliver(obj, origin, pathTarget);
						}
						freeCivilian(obj);
						return 0.4;
					}
					else {
						return 0.2;
					}
				}
				else if(curRegion is null) {
					//Move to closest region
					vec3d pos = nextRegion.position + (nextRegion.position - obj.position).normalized(nextRegion.radius * 0.85);
					obj.maxAcceleration = ACC_INTERSYSTEM;
					if(obj.moveTo(pos, moveId, enterOrbit=false)) {
						moveId = -1;
						return 0.4;
					}
					else {
						return 0.2;
					}
				}
				else {
					//Find the next region to path to
					TradePath path(obj.owner);
					path.generate(getSystem(curRegion), getSystem(destRegion));

					if(path.pathSize < 2 || !path.valid) {
						freeCivilian(obj);
						return 0.4;
					}
					else {
						@prevRegion = curRegion;
						@nextRegion = path.pathNode[1].object;
						awaitingIntermediate = true;
						@intermediate = null;
						if(curRegion.hasTradeStation(obj.owner))
							curRegion.getTradeStation(obj, obj.owner, obj.position);
						else if(cargoType == CT_Goods)
							curRegion.getTradePlanet(obj, obj.owner);
						else
							awaitingIntermediate = false;
						leavingRegion = false;
					}
				}
			}
			if(!leavingRegion) {
				if(intermediate !is null) {
					if(obj.moveTo(intermediate, moveId, distance=10.0, enterOrbit=false)) {
						moveId = -1;
						@intermediate = null;
						return 0.4;
					}
					else {
						return 0.2;
					}
				}
				else {
					if(moveId == -1 && !getSystem(prevRegion).isSpatialAdjacent(getSystem(nextRegion)))  {
						leavingRegion = true;
						return 0.5;
					}
					vec3d leaveDest;
					if(prevRegion is null)
						leaveDest = obj.position;
					else
						leaveDest = prevRegion.position + (nextRegion.position - prevRegion.position).normalized(prevRegion.radius * 0.85) + random3d(0, DEST_RANGE);
					obj.maxAcceleration = ACC_SYSTEM;
					if(obj.moveTo(leaveDest, moveId, enterOrbit=false)) {
						moveId = -1;
						leavingRegion = true;
						return 0.5;
					}
				}
			}
		}
		return 0.2;
	}

	void setOrigin(Object@ origin) {
		@this.origin = origin;
		delta = true;
	}

	void pathTo(Civilian& obj, Object@ origin, Object@ target, Object@ stopAt = null) {
		@pathTarget = target;
		@prevRegion = null;
		@nextRegion = null;
		@intermediate = stopAt;
		@this.origin = origin;
		pickedUp = false;
		delta = true;
		leavingRegion = false;
	}

	void pathTo(Civilian& obj, Object@ target) {
		@pathTarget = target;
		@prevRegion = null;
		@nextRegion = null;
		@origin = null;
		@intermediate = null;
		pickedUp = true;
		delta = true;
		leavingRegion = false;
	}

	void damage(Civilian& obj, DamageEvent& evt, double position, const vec2d& direction) {
		if(!obj.valid || obj.destroying)
			return;
		obj.engaged = true;
		Health = max(0.0, Health - evt.damage);
		delta = true;
		if(Health <= 0.0) {
			if(cargoWorth > 0) {
				Empire@ other = evt.obj.owner;
				if(other !is null && other.major) {
					other.addBonusBudget(cargoWorth);
					cargoWorth = 0;
				}
			}
			if(cargoResource !is null) {
				for(uint i = 0, cnt = cargoResource.hooks.length; i < cnt; ++i)
					cargoResource.hooks[i].onTradeDestroy(obj, origin, pathTarget, evt.obj);
			}
			obj.destroy();
		}
	}

	void _writeDelta(const Civilian& obj, Message& msg) {
		msg.writeSmall(cargoType);
		msg.writeSmall(cargoWorth);
		msg.writeBit(pickedUp);
		msg.writeFixed(obj.health/obj.maxHealth);
		if(cargoResource !is null) {
			msg.write1();
			msg.writeLimited(cargoResource.id, getResourceCount()-1);
		}
		else {
			msg.write0();
		}
	}

	void syncInitial(const Civilian& obj, Message& msg) {
		if(obj.hasMover) {
			msg.write1();
			obj.writeMover(msg);
		}
		else {
			msg.write0();
		}
		msg << type;
		_writeDelta(obj, msg);
	}

	void syncDetailed(const Civilian& obj, Message& msg) {
		if(obj.hasMover) {
			msg.write1();
			obj.writeMover(msg);
		}
		else {
			msg.write0();
		}
		_writeDelta(obj, msg);
	}

	bool syncDelta(const Civilian& obj, Message& msg) {
		bool used = false;
		if(obj.hasMover && obj.writeMoverDelta(msg))
			used = true;
		else
			msg.write0();
		if(delta) {
			used = true;
			delta = false;
			msg.write1();
			_writeDelta(obj, msg);
		}
		else {
			msg.write0();
		}
		return used;
	}
};

void dumpPlanetWaitTimes() {
	uint cnt = playerEmpire.planetCount;
	double avg = 0.0, maxTime = 0.0;
	for(uint i = 0; i < cnt; ++i) {
		Planet@ pl = playerEmpire.planetList[i];
		if(pl !is null && pl.getNativeResourceDestination(playerEmpire, 0) !is null) {
			double timer = pl.getCivilianTimer();
			print(pl.name+" -- "+timer);
			avg += timer;
			if(timer > maxTime)
				maxTime = timer;
		}
	}
	avg /= double(cnt);
	print(" AVERAGE: "+avg);
	print(" MAX: "+maxTime);
}
