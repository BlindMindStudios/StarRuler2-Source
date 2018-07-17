import orders.Order;
from orders.GotoOrder import GotoOrder;
from orders.MoveOrder import MoveOrder;
from orders.AttackOrder import AttackOrder;
from orders.AbilityOrder import AbilityOrder;
from orders.CaptureOrder import CaptureOrder;
from orders.HyperdriveOrder import HyperdriveOrder;
from orders.JumpdriveOrder import JumpdriveOrder;
from orders.FlingOrder import FlingOrder;
from orders.PickupOrder import PickupOrder;
from orders.ScanOrder import ScanOrder;
from orders.RefreshOrder import RefreshOrder;
from orders.OddityGateOrder import OddityGateOrder;
from orders.SlipstreamOrder import SlipstreamOrder;
from orders.AutoExploreOrder import AutoExploreOrder;
from orders.WaitOrder import WaitOrder;
from resources import getBuildCost, getMaintenanceCost, MoneyType, getLaborCost;
import abilities;
import orbitals;
import saving;
import cargo;
import systems;
import ftl;
import util.target_search;
import ship_groups;
import design_settings;

tidy class ActiveConstruction {
	uint id;
	const Design@ dsg;
	Object@ shipyard;

	void load(SaveFile& msg){
		msg >> id;
		msg >> dsg;
		msg >> shipyard;
	}

	void save(SaveFile& msg) {
		msg << id;
		msg << dsg;
		msg << shipyard;
	}
};

tidy class Formation : Savable {
	void save(SaveFile& file) {}
	void load(SaveFile& file) {}
	void reset(double minRad, double maxRad) {}
	vec3d getNext(Object& support) { return vec3d(); }
};

//Factor of new design cost as minimum for retrofit
const double RETROFIT_MIN_PCT = 0.3;

tidy class LeaderAI : Component_LeaderAI, Savable {
	Order@ order;
	bool orderDelta = false;
	uint firstOrder = OT_INVALID;

	Formation@ formation = IntersperseFormation();
	bool formationDelta = false;

	Object@[] supports;
	GroupData@[] groupData;

	AutoMode autoMode = AM_AreaBound;
	EngagementBehaviour engageBehave = EB_CloseIn;
	EngagementRange engageType = ER_SupportMin;
	double autoArea = 1000.0;
	double engagementRange = 200.0;
	double ghostHP = 0.0;
	double ghostDPS = 0.0;
	double orderedHP = 0.0;
	double orderedDPS = 0.0;
	double fleetHP = 0.0;
	double fleetDPS = 0.0;
	double fleetMaxHP = 0.0;
	double fleetMaxDPS = 0.0;
	double bonusDPS = 0.0;
	double needExperience = 0.0;
	bool registered = false;
	bool allowSatellites = false;

	bool FreeRaiding = false;
	double RaidRange = 1000.0;

	//Whether to automaticall pluck supports of planets
	bool autoFill = true;
	//Whether to automatically buy new supports until full
	bool autoBuy = false;
	//Whether to record dead supports for the future
	bool rememberGhosts = true;
	//Whether fleets can autofill from this
	bool AllowFillFrom = false;

	AutoState autoState = AS_None;
	vec3d initialPosition;

	float fleetEffectiveness = 1.f;
	float permanentEffectiveness = 0.f;

	uint supplyCapacity = 0;
	uint supplyUsed = 0;
	uint supplyGhost = 0;
	uint supplyOrdered = 0;
	uint supplySatellite = 0;

	uint nextConstructionId = 0;
	ActiveConstruction@[] activeConstructions;
	double constructionTimer = 0;
	bool canGain = true;

	bool delta = false;
	array<Object@>@ removedSupports;
	array<Object@>@ addedSupports;

	FleetPlaneNode@ node;

	LeaderAI() {
	}

	void load(SaveFile& msg) {
		uint cnt = 0;
		msg >> cnt;
		supports.length = cnt;
		for(uint i = 0; i < cnt; ++i)
			msg >> supports[i];

		msg >> cnt;
		groupData.length = cnt;
		for(uint i = 0; i < cnt; ++i) {
			@groupData[i] = GroupData();
			groupData[i].load(msg);

			supplyGhost += groupData[i].dsg.size * groupData[i].ghost;
			supplyOrdered += groupData[i].dsg.size * groupData[i].ordered;

			orderedHP += double(groupData[i].ordered) * groupData[i].dsg.totalHP;
			orderedDPS += double(groupData[i].ordered) * groupData[i].dsg.total(SV_DPS);
		}

		uint mode = 0, state = 0, beh = 0, type = 0;
		msg >> mode;
		msg >> autoArea;
		msg >> engagementRange;
		msg >> state;
		msg >> initialPosition;
		msg >> ghostHP;
		msg >> ghostDPS;
		msg >> canGain;
		if(msg >= SV_0042)
			msg >> bonusDPS;
		if(msg >= SV_0066) {
			msg >> beh;
			msg >> type;

			engageBehave = EngagementBehaviour(beh);
			engageType = EngagementRange(type);
		}
		if(msg >= SV_0116)
			msg >> registered;
		else
			registered = true;

		autoMode = AutoMode(mode);
		autoState = AutoState(state);

		msg >> fleetEffectiveness;
		if(msg >= SV_0015)
			msg >> permanentEffectiveness;
		msg >> supplyCapacity;
		msg >> supplyUsed;
		msg >> nextConstructionId;

		if(msg >= SV_0073) {
			msg >> autoFill >> autoBuy;
			msg >> rememberGhosts;
		}
		if(msg >= SV_0146)
			msg >> AllowFillFrom;
		if(msg >= SV_0149)
			msg >> allowSatellites;

		msg >> cnt;
		activeConstructions.length = cnt;
		for(uint i = 0; i < cnt; ++i) {
			@activeConstructions[i] = ActiveConstruction();
			activeConstructions[i].load(msg);
		}

		msg >> constructionTimer;

		msg >> cnt;
		Order@ prev;
		for(uint i = 0; i < cnt; ++i) {
			Order@ ord;

			uint8 type = 0;
			msg >> type;
			switch(type) {
				case OT_Attack:
					@ord = AttackOrder(msg);
				break;
				case OT_Goto:
					@ord = GotoOrder(msg);
				break;
				case OT_Hyperdrive:
					@ord = HyperdriveOrder(msg);
				break;
				case OT_Jumpdrive:
					@ord = JumpdriveOrder(msg);
				break;
				case OT_Fling:
					@ord = FlingOrder(msg);
				break;
				case OT_Move:
					@ord = MoveOrder(msg);
				break;
				case OT_PickupOrder:
					@ord = PickupOrder(msg);
				break;
				case OT_Capture:
					@ord = CaptureOrder(msg);
				break;
				case OT_Scan:
					@ord = ScanOrder(msg);
				break;
				case OT_Refresh:
					@ord = RefreshOrder(msg);
				break;
				case OT_OddityGate:
					@ord = OddityGateOrder(msg);
				break;
				case OT_Slipstream:
					@ord = SlipstreamOrder(msg);
				break;
				case OT_Ability:
					@ord = AbilityOrder(msg);
				break;
				case OT_AutoExplore:
					@ord = AutoExploreOrder(msg);
				break;
				case OT_Wait:
					@ord = WaitOrder(msg);
				break;
			}

			if(ord !is null) {
				if(prev is null) {
					@order = ord;
				}
				else {
					@prev.next = ord;
					@ord.prev = prev;
				}
				@prev = ord;
			}
			if(order !is null)
				firstOrder = order.type;
		}

		if(msg >= SV_0068)
			msg >> formation;
		if(msg >= SV_0142)
			msg >> needExperience;
		else
			needExperience = INFINITY;

		if(msg >= SV_0144) {
			msg >> FreeRaiding;
			msg >> RaidRange;
		}
	}

	double get_GhostHP() const {
		return ghostHP;
	}

	double get_GhostDPS() const {
		return ghostDPS;
	}

	void save(SaveFile& msg) {
		uint cnt = supports.length;
		msg << cnt;
		for(uint i = 0; i < cnt; ++i)
			msg << supports[i];

		cnt = groupData.length;
		msg << cnt;
		for(uint i = 0; i < cnt; ++i)
			groupData[i].save(msg);

		msg << uint(autoMode);
		msg << autoArea;
		msg << engagementRange;
		msg << uint(autoState);
		msg << initialPosition;
		msg << ghostHP;
		msg << ghostDPS;
		msg << canGain;
		msg << bonusDPS;
		msg << uint(engageBehave);
		msg << uint(engageType);
		msg << registered;

		msg << fleetEffectiveness;
		msg << permanentEffectiveness;
		msg << supplyCapacity;
		msg << supplyUsed;
		msg << nextConstructionId;

		msg << autoFill << autoBuy;
		msg << rememberGhosts;
		msg << AllowFillFrom;
		msg << allowSatellites;

		cnt = activeConstructions.length;
		msg << cnt;
		for(uint i = 0; i < cnt; ++i)
			activeConstructions[i].save(msg);

		msg << constructionTimer;

		cnt = orderCount;
		msg << cnt;
		
		Order@ ord = order;
		while(ord !is null) {
			ord.save(msg);
			@ord = ord.next;
		}

		msg << formation;
		msg << needExperience;

		msg << FreeRaiding;
		msg << RaidRange;
	}

	float getFleetEffectiveness() const {
		return fleetEffectiveness * getBaseFleetEffectiveness();
	}

	float getBaseFleetEffectiveness() const {
		if(permanentEffectiveness < 0)
			return pow(0.5, -2.0 * double(permanentEffectiveness));
		return 1.0 + permanentEffectiveness;
	}

	void setFleetEffectiveness(float value) {
		fleetEffectiveness = value;
	}

	void addExperience(Object& obj, double amount) {
		double size = 500.0;
		if(obj.isShip) {
			Ship@ ship = cast<Ship>(obj);
			size = ship.blueprint.design.size;
		}

		amount *= obj.owner.ExperienceGainFactor;
		needExperience -= amount;
		if(needExperience <= 0) {
			int curLevel = obj.getStatusStackCountAny(levelStatus);

			while(needExperience <= 0) {
				obj.addStatus(levelStatus);
				curLevel += 1;

				needExperience += size * (config::EXPERIENCE_BASE_AMOUNT + config::EXPERIENCE_INCREASE_AMOUNT * curLevel);
			}
		}
		delta = true;
	}

	void resetLevelExperience(Object& obj, bool resetLevels = false) {
		double size = 500.0;
		if(obj.isShip) {
			Ship@ ship = cast<Ship>(obj);
			size = ship.blueprint.design.size;
		}
		int curLevel = 0;
		if(resetLevels)
			obj.removeStatusType(levelStatus);
		else
			curLevel = obj.getStatusStackCountAny(levelStatus);
		needExperience = size * (config::EXPERIENCE_BASE_AMOUNT + config::EXPERIENCE_INCREASE_AMOUNT * curLevel);
	}

	void recalculateLevels(Object& obj, int prevSize, int newSize) {
		int gainedXP = 0;
		int curLevel = obj.getStatusStackCountAny(levelStatus);
		for(int i = 0; i < curLevel; ++i)
			gainedXP += double(prevSize) * (config::EXPERIENCE_BASE_AMOUNT + config::EXPERIENCE_INCREASE_AMOUNT * double(i));

		int curTotal = double(prevSize) * (config::EXPERIENCE_BASE_AMOUNT + config::EXPERIENCE_INCREASE_AMOUNT * double(curLevel));
		gainedXP += (curTotal - needExperience);

		resetLevelExperience(obj, resetLevels=true);
		addExperience(obj, gainedXP);
	}

	double getRemainingExp() const {
		return needExperience;
	}

	void modFleetEffectiveness(Object& obj, float mod) {
		permanentEffectiveness += mod;
		if(obj.isShip)
			cast<Ship>(obj).blueprint.delta = true;
		delta = true;
	}
	
	void set_engageRange(Object& obj, double radius) {
		engagementRange = radius - getFormationRadius(obj);
	}

	bool get_canGainSupports() const {
		return canGain;
	}

	void set_canGainSupports(bool value) {
		if(canGain != value) {
			canGain = value;
		}
	}

	uint get_supportCount() {
		return supports.length;
	}

	Object@ get_supportShip(uint index) {
		if(index >= supports.length)
			return null;
		return supports[index];
	}
	
	void idleAllSupports() {
		for(uint i = 0, cnt = supports.length; i < cnt; ++i)
			supports[i].supportIdle();
	}
	
	void standDownAllSupports() {
		for(uint i = 0, cnt = supports.length; i < cnt; ++i)
			supports[i].doRaids = false;
	}
	
	void updateFleetStrength(Object& obj) {
		double hp = 0.0, dps = 0.0, maxHP = 0.0, maxDPS = 0.0;
		
		if(obj.isShip) {
			Ship@ ship = cast<Ship>(obj);
			auto@ bp = ship.blueprint;

			hp = bp.currentHP * bp.hpFactor + ship.Shield;
			dps = ship.DPS * bp.shipEffectiveness;
			
			maxHP = bp.design.totalHP - bp.removedHP + ship.MaxShield;
			maxDPS = ship.MaxDPS;
		}
		if(obj.isOrbital) {
			Orbital@ orb = cast<Orbital>(obj);
			hp = orb.health + orb.armor;
			maxHP = orb.maxHealth + orb.maxArmor;
			maxDPS = orb.dps;
			dps = maxDPS * orb.efficiency;
		}

		for(uint i = 0, cnt = supports.length; i < cnt; ++i) {
			Ship@ ship = cast<Ship>(supports[i]);
			if(ship !is null) {
				auto@ bp = ship.blueprint;
				hp += bp.currentHP * bp.hpFactor + ship.Shield;
				dps += ship.DPS * bp.shipEffectiveness;
				maxHP += bp.design.totalHP - bp.removedHP + ship.MaxShield;
				maxDPS += ship.MaxDPS;
			}
		}
		
		fleetHP = hp;
		fleetDPS = dps;
		fleetMaxHP = maxHP;
		fleetMaxDPS = maxDPS;
	}

	void modBonusDPS(double amount) {
		bonusDPS += amount;
		delta = true;
	}
	
	double getFleetHP() const {
		return fleetHP;
	}
	
	double getFleetDPS() const {
		return fleetDPS + bonusDPS;
	}

	double getFleetStrength(const Object& obj) const {
		return fleetHP * (fleetDPS + bonusDPS);
	}

	double getFleetMaxStrength(const Object& obj) const {
		return (fleetMaxHP + ghostHP + orderedHP) * (fleetMaxDPS + bonusDPS + ghostDPS + orderedDPS) * getBaseFleetEffectiveness();
	}

	int getRetrofitCost(const Object& obj) const {
		int cost = 0;
		bool have = false;
		const Ship@ ship = cast<const Ship>(obj);
		if(ship !is null) {
			const Design@ from = ship.blueprint.design;
			if(from !is null) {
				@from = from.mostUpdated();
				const Design@ to = from.newest().mostUpdated();
				if(from !is to && from.hasTag(ST_Support) == to.hasTag(ST_Support) && from.hasTag(ST_Satellite) == to.hasTag(ST_Satellite)) {
					int fromCost = getBuildCost(from);
					int toCost = getBuildCost(to);
					cost += max(toCost - fromCost, int(ceil(toCost * RETROFIT_MIN_PCT)));
					have = true;
				}
			}
		}

		for(uint i = 0, cnt = groupData.length; i < cnt; ++i) {
			GroupData@ dat = groupData[i];
			const Design@ from = dat.dsg;
			if(from is null)
				continue;
			@from = from.mostUpdated();
			const Design@ to = from.newest().mostUpdated();
			if(from !is to && from.hasTag(ST_Support) == to.hasTag(ST_Support) && from.hasTag(ST_Satellite) == to.hasTag(ST_Satellite)) {
				int fromCost = getBuildCost(from);
				int toCost = getBuildCost(to);
				cost += max(toCost - fromCost, int(ceil(toCost * RETROFIT_MIN_PCT))) * dat.amount;
				have = true;
			}
		}

		if(!have)
			return -1;
		else
			return cost;
	}

	double getRetrofitLabor(const Object& obj) const {
		double cost = 0;
		bool have = false;
		const Ship@ ship = cast<const Ship>(obj);
		if(ship !is null) {
			const Design@ from = ship.blueprint.design;
			if(from !is null) {
				@from = from.mostUpdated();
				const Design@ to = from.newest().mostUpdated();
				if(from !is to && from.hasTag(ST_Support) == to.hasTag(ST_Support) && from.hasTag(ST_Satellite) == to.hasTag(ST_Satellite)) {
					double fromCost = getLaborCost(from);
					double toCost = getLaborCost(to);
					cost += max(toCost - fromCost, toCost * RETROFIT_MIN_PCT);
					have = true;
				}
			}
		}

		for(uint i = 0, cnt = groupData.length; i < cnt; ++i) {
			GroupData@ dat = groupData[i];
			const Design@ from = dat.dsg;
			if(from is null)
				continue;
			@from = from.mostUpdated();
			const Design@ to = from.newest().mostUpdated();
			if(from !is to && from.hasTag(ST_Support) == to.hasTag(ST_Support) && from.hasTag(ST_Satellite) == to.hasTag(ST_Satellite)) {
				double fromCost = getLaborCost(from);
				double toCost = getLaborCost(to);
				cost += max(toCost - fromCost, toCost * RETROFIT_MIN_PCT) * dat.amount;
				have = true;
			}
		}

		if(!have)
			return -1;
		else
			return cost;
	}

	void retrofitFleetAt(Object& obj, Object@ at, Object@ constructFrom) {
		int cost = 0, maint = 0;
		double labor = 0.0;
		bool have = false;
		array<const Design@> designs;

		for(int i = -1, cnt = int(supports.length); i < cnt; ++i) {
			Ship@ ship;
			if(i == -1)
				@ship = cast<Ship>(obj);
			else
				@ship = cast<Ship>(supports[i]);

			if(ship !is null && ship.RetrofittingAt is null) {
				const Design@ from = ship.blueprint.design;
				if(from is null)
					continue;
				@from = from.mostUpdated();
				const Design@ to = from.newest().mostUpdated();
				if(from !is to && from.hasTag(ST_Support) == to.hasTag(ST_Support) && from.hasTag(ST_Satellite) == to.hasTag(ST_Satellite)) {
					int fromCost = 0, fromMaint = 0;
					double fromLabor = 0;
					getBuildCost(from, fromCost, fromMaint, fromLabor);

					int toCost = 0, toMaint = 0;
					double toLabor = 0;
					getBuildCost(to, toCost, toMaint, toLabor);

					cost += max(toCost - fromCost, int(ceil(toCost * RETROFIT_MIN_PCT)));
					labor += max(toLabor - fromLabor, toLabor * RETROFIT_MIN_PCT);
					maint += max(toMaint - fromMaint, 0);

					ship.startRetrofit(at, to);
					if(hasDesignCosts(to))
						designs.insertLast(to);
					have = true;
				}
			}
		}

		if(have) {
			at.startRetrofitConstruction(obj, cost, labor, maint, constructFrom=constructFrom);
			for(uint i = 0, cnt = designs.length; i < cnt; ++i)
				at.retrofitDesignCost(obj, designs[i]);
			at.retrofitDesignCostFinish(obj);
		}
	}

	void stopFleetRetrofit(Object& obj, Object@ at) {
		for(int i = -1, cnt = int(supports.length); i < cnt; ++i) {
			Ship@ ship;
			if(i == -1)
				@ship = cast<Ship>(obj);
			else
				@ship = cast<Ship>(supports[i]);

			if(ship !is null)
				ship.stopRetrofit(at);
		}
	}

	void finishFleetRetrofit(Object& obj, Object@ at) {
		for(int i = -1, cnt = int(supports.length); i < cnt; ++i) {
			Ship@ ship;
			if(i == -1)
				@ship = cast<Ship>(obj);
			else
				@ship = cast<Ship>(supports[i]);

			if(ship !is null)
				ship.completeRetrofit(at);
		}
	}

	void takeoverFleet(Object& obj, Empire@ newOwner, double supportRatio, bool moveToTerritory) {
		@obj.owner = newOwner;
		for(uint i = 0, cnt = supports.length; i < cnt; ++i) {
			if(supportRatio >= 1.0 || randomd() <= supportRatio)
				@supports[i].owner = newOwner;
		}

		if(moveToTerritory && obj.hasMover) {
			auto@ closest = getClosestSystem(obj.position, newOwner);
			if(closest.object !is obj.region)
				obj.addGotoOrder(closest.object);
		}
	}

	uint get_SupplyUsed() const {
		return supplyUsed;
	}

	uint get_SupplyCapacity() const {
		return supplyCapacity;
	}

	uint get_SupplyGhost() const {
		return supplyGhost;
	}

	uint get_SupplyOrdered() const {
		return supplyOrdered;
	}

	uint get_SupplySatellite() const {
		return supplySatellite;
	}

	uint get_SupplyAvailable() const {
		uint supcap = supplyCapacity;
		uint supUsed = supplyUsed;
		if(supcap > supUsed)
			return supcap - supUsed;
		else
			return 0;
	}

	bool canTakeSupport(int size, bool pickup) const {
		if(!canGain)
			return false;
		if(pickup)
			return supplyUsed - supplyGhost + uint(size) <= supplyCapacity;
		else
			return supplyUsed + uint(size) <= supplyCapacity;
	}

	uint getGhostCount(const Design@ dsg) const {
		int ind = getGroupDataIndex(dsg, false);
		if(ind == -1)
			return 0;
		return groupData[ind].ghost;
	}

	uint getSupportCount(const Design@ dsg) const {
		int ind = getGroupDataIndex(dsg, false);
		if(ind == -1)
			return 0;
		return groupData[ind].amount;
	}
	
	bool get_hasOrderedSupports() const {
		return supplyOrdered > 0;
	}

	void orderTick(Object& obj, double time) {
		//Any order that places the object out of its
		//bound area is immediately canceled while we return
		if(autoState == AS_Attacking) {
			if(autoMode == AM_AreaBound) {
				if(obj.position.distanceTo(initialPosition) > autoArea)
					clearOrders(obj);
			}
			else if(autoMode == AM_RegionBound) {
				auto@ ao = cast<AttackOrder>(order);
				if(obj.region is null || (ao !is null && ao.target.region !is obj.region))
					clearOrders(obj);
			}
		}

		//Do actions required for orders
		Order@ ord = order;
		while(ord !is null) {
			switch(ord.tick(obj, time)) {
				case OS_BLOCKING:
					//Stop doing anything if the order blocked
				return;
				case OS_NONBLOCKING:
					//Just continue
					@ord = ord.next;
				break;
				case OS_COMPLETED:
					ord.destroy();
					//Remove order from the list and continue
					if(ord.prev is null) {
						@ord = ord.next;
						@order = ord;
						if(ord !is null)
							@ord.prev = null;
					}
					else {
						Order@ next = ord.next;
						if(next !is null)
							@next.prev = ord.prev;
						@ord.prev.next = next;
					}
					orderDelta = true;
				break;
			}
		}
		if(order !is null)
			firstOrder = order.type;
		else
			firstOrder = OT_INVALID;

		//Object AI is handled here. Every order takes priority
		//over the AI and can block it.
		if(autoState == AS_None) {
			initialPosition = obj.position;
		}
		else if(autoState == AS_Returning) {
			if(initialPosition.distanceTo(obj.position) < obj.radius * 2) {
				addStopOrder(obj, false);
				autoState = AS_None;
			}
		}

		//Try to find enemies in the bound area
		if((autoMode != AM_HoldPosition && autoMode != AM_HoldFire) && obj.hasMover && !obj.hasOrbit && obj.getLockedOrbit() is null && (engagementRange >= 0 || supports.length > 0) && (!obj.isShip || !cast<Ship>(obj).getHoldFire())) {
			Object@ target;
			if(autoMode == AM_RegionBound) {
				Region@ reg = obj.region;
				if(reg !is null)
					@target = findEnemy(obj, obj, obj.owner, reg.position, reg.radius, ignoreSecondary = true);
			}
			else
				@target = findEnemy(obj, obj, obj.owner, initialPosition, autoArea, ignoreSecondary = true);
			//Always target flagships
			if(target !is null && target.isShip && target.hasSupportAI)
				@target = cast<Ship>(target).Leader;
			if(target !is null && target.isPlanet)
				@target = null;
			if(target is null) {
				//Return state to normal once we've returned to our position
				if(autoState != AS_None) {
					if(autoMode == AM_Unbound) {
						autoState = AS_None;
						addStopOrder(obj, false);
					}
					else if(autoMode == AM_AreaBound || autoMode == AM_RegionBound) {
						if(initialPosition.distanceTo(obj.position) < obj.radius * 2) {
							addStopOrder(obj, false);
							autoState = AS_None;
						}
						else {
							addMoveOrder(obj, initialPosition, false);
							autoState = AS_Returning;
						}
					}
				}
			}
			else {
				//Attack a particular target
				if(autoMode == AM_AreaBound)
					addAttackOrder(obj, target, initialPosition, autoArea, engageBehave == EB_KeepDistance, false);
				else if(autoMode == AM_RegionBound)
					addAttackOrder(obj, target, false);
				else
					addAttackOrder(obj, target, vec3d(), 0, engageBehave == EB_KeepDistance, false);
				autoState = AS_Attacking;
			}
		}
	}
	
	bool get_hasOrders() {
		return order !is null;
	}

	bool hasOrder(uint type, bool checkQueued = false) {
		if(order is null)
			return false;
		if(!checkQueued)
			return order.type == int(type);
		Order@ ord = @order;
		while(ord !is null) {
			if(ord.type == int(type))
				return true;
			@ord = ord.next;
		}
		return false;
	}

	uint get_orderCount() {
		uint ordCount = 0;
		Order@ ord = @order;
		while(ord !is null) {
			ordCount += 1;
			@ord = ord.next;
		}
		return ordCount;
	}

	Order@ getOrder(uint num) {
		Order@ ord = @order;
		while(ord !is null && num != 0) {
			num -= 1;
			@ord = ord.next;
		}
		return ord;
	}

	string get_orderName(uint num) {
		Order@ ord = getOrder(num);
		if(ord !is null)
			return ord.name;
		else
			return "";
	}
	
	uint get_firstOrderType() {
		return firstOrder;
	}

	uint get_orderType(uint num) {
		Order@ ord = getOrder(num);
		if(ord !is null)
			return ord.type;
		else
			return OT_INVALID;
	}

	bool get_orderHasMovement(uint num) {
		Order@ ord = getOrder(num);
		if(ord !is null)
			return ord.hasMovement;
		else
			return false;
	}

	vec3d get_orderMoveDestination(const Object& obj, uint num) {
		Order@ ord = getOrder(num);
		if(ord !is null)
			return ord.getMoveDestination(obj);
		else
			return vec3d();
	}

	vec3d get_finalMoveDestination(const Object& obj) {
		Order@ ord = order;
		vec3d pos = obj.position;
		while(ord !is null) {
			if(ord.hasMovement)
				pos = ord.getMoveDestination(obj);
			@ord = ord.next;
		}
		return pos;
	}

	void setHoldPosition(Object& obj, bool hold) {
		if(hold)
			setAutoMode(obj, AM_HoldPosition);
		else
			setAutoMode(obj, AM_AreaBound);
	}

	uint getAutoMode() {
		return uint(autoMode);
	}

	void setAutoMode(Object& obj, uint type) {
		if(type == uint(autoMode))
			return;

		if(autoMode == AM_HoldFire) {
			Ship@ ship = cast<Ship>(obj);
			if(ship !is null)
				ship.setHoldFire(false);
		}
		autoMode = AutoMode(type);
		if(autoMode == AM_HoldFire) {
			Ship@ ship = cast<Ship>(obj);
			if(ship !is null)
				ship.setHoldFire(true);
		}

		orderDelta = true;
	}

	uint getEngageType() {
		return uint(engageType);
	}

	void compEngageRange(Object& obj) {
		Ship@ ship = cast<Ship>(obj);
		if(ship is null)
			return;
		if(engageType == ER_RaidingOnly) {
			engagementRange = RaidRange;
		}
		else if(engageType == ER_FlagshipMax) {
			engagementRange = ship.maxEngagementRange * 0.95;
		}
		else if(engageType == ER_FlagshipMin) {
			engagementRange = ship.minEngagementRange * 0.95;
		}
		else if(engageType == ER_SupportMin) {
			engagementRange = ship.minEngagementRange * 0.95;
			double fleetRad = getFormationRadius(obj) * 0.4; //Make sure at roughly a quarter of the fleet circle could engage at this range
			for(uint i = 0, cnt = supports.length; i < cnt; ++i) {
				Ship@ supship = cast<Ship>(supports[i]);
				engagementRange = min(engagementRange, supship.minEngagementRange + fleetRad);
			}
		}
	}

	void addEngageRange(Object& obj, Object& sup) {
		if(engageType == ER_SupportMin) {
			Ship@ supship = cast<Ship>(sup);
			if(supship !is null) {
				if(supship.minEngagementRange == 0)
					formationDelta = true;
				else
					engagementRange = min(engagementRange, supship.minEngagementRange);
			}
		}
	}

	void setEngageType(Object& obj, uint type) {
		engageType = EngagementRange(type);
		compEngageRange(obj);
		orderDelta = true;
	}

	uint getEngageBehave() {
		return uint(engageBehave);
	}

	void setEngageBehave(uint type) {
		engageBehave = EngagementBehaviour(type);
		orderDelta = true;
	}

	bool get_autoBuySupports() {
		return autoBuy;
	}

	void set_autoBuySupports(bool value) {
		autoBuy = value;
		orderDelta = true;
	}

	bool get_autoFillSupports() {
		return autoFill;
	}

	bool get_canHaveSatellites() const {
		return allowSatellites;
	}

	void set_autoFillSupports(bool value) {
		autoFill = value;
		orderDelta = true;
	}

	bool get_allowFillFrom() {
		return AllowFillFrom;
	}

	void set_allowFillFrom(bool value) {
		AllowFillFrom = value;
		orderDelta = true;
	}

	void clearOrders(Object& obj) {
		//Delete all orders we can, move any orders that persist to a new chain
		if(order !is null) {
			Order@ cur = order;
			
			Order@ chain = null;
			@order = null;
			firstOrder = OT_INVALID;
		
			while(cur !is null) {
				Order@ next = cur.next;
				if(!cur.cancel(obj)) {
					@cur.next = null;
					if(order is null)
						@order = cur;
					else //@chain !is null
						@chain.next = cur;
					
					@chain = cur;
				}
				else {
					cur.destroy();
				}
				@cur = next;
			}
			
			orderDelta = true;
		}
		if(obj.hasMover && obj.isMoving)
			obj.stopMoving();
	}

	void clearTopOrder(Object& obj) {
		if(order !is null) {
			if(order.cancel(obj)) {
				order.destroy();
				@order = order.next;
			}
		}
		if(order is null) {
			if(obj.hasMover && obj.isMoving)
				obj.stopMoving();
		}
		if(order !is null)
			firstOrder = order.type;
		else
			firstOrder = OT_INVALID;
	}
	
	void insertOrder(Object& obj, Order@ ord, uint index) {
		orderDelta = true;
		
		if(order is null) {
			@order = ord;
			return;
		}
		
		if(index == 0) {
			@order.prev = ord;
			@ord.next = order;
			@order = ord;
			return;
		}
		
		Order@ o = order;
		while(index > 0 && o.next !is null) {
			@o = o.next;
			index--;
		}
		
		@ord.next = o.next;
		@ord.prev = o;
		
		if(o.next !is null)
			@o.next.prev = ord;
		@o.next = ord;

		if(order !is null)
			firstOrder = order.type;
		else
			firstOrder = OT_INVALID;
	}

	void addOrder(Object& obj, Order@ ord, bool append) {
		autoState = AS_None;
		orderDelta = true;
		
		if(!append || order is null) {
			clearOrders(obj);
			if(order is null) {
				@order = ord;
				return;
			}
		}
		
		//If we only cancelled some orders, or we wanted to append, we append now
		Order@ last = order;
		while(last.next !is null)
			@last = last.next;
		@last.next = ord;
		@ord.prev = last;

		if(order !is null)
			firstOrder = order.type;
		else
			firstOrder = OT_INVALID;
	}

	void addStopOrder(Object& obj, bool append) {
		//TODO: Actual stop order.
		addMoveOrder(obj, obj.position, append);
	}

	void addGotoOrder(Object& obj, Object& target, bool append) {
		addOrder(obj, GotoOrder(target, obj.radius + 45.f + target.radius), append);
		obj.wake();
	}

	void addPickupOrder(Object& obj, Pickup& target, bool append) {
		addOrder(obj, PickupOrder(target), append);
		obj.wake();
	}

	void addAttackOrder(Object& obj, Object& target, bool append) {
		double range = engagementRange;
		if(autoMode == AM_HoldFire)
			setAutoMode(obj, AM_HoldPosition);
		addOrder(obj, AttackOrder(target, range), append);
		obj.wake();
	}

	void addAttackOrder(Object& obj, Object& target, vec3d bindPos, double bindDist, bool closeIn, bool append) {
		double range = engagementRange;
		if(autoMode == AM_HoldFire)
			setAutoMode(obj, AM_HoldPosition);
		addOrder(obj, AttackOrder(target, range, bindPos, bindDist, closeIn), append);
		obj.wake();
	}

	void addAbilityOrder(Object& obj, int abilityId, vec3d target, bool append) {
		double range = obj.getAbilityRange(abilityId, target);
		addOrder(obj, AbilityOrder(abilityId, target, range), append);
		obj.wake();
	}

	void addAbilityOrder(Object& obj, int abilityId, Object@ target, bool append) {
		double range = obj.getAbilityRange(abilityId, target);
		addOrder(obj, AbilityOrder(abilityId, target, range), append);
		obj.wake();
	}

	void addAbilityOrder(Object& obj, int abilityId, vec3d target, double _range, bool append) {
		double range = obj.getAbilityRange(abilityId, target);
		addOrder(obj, AbilityOrder(abilityId, target, range), append);
		obj.wake();
	}

	void addAbilityOrder(Object& obj, int abilityId, Object@ target, double _range, bool append) {
		double range = obj.getAbilityRange(abilityId, target);
		addOrder(obj, AbilityOrder(abilityId, target, range), append);
		obj.wake();
	}

	void addCaptureOrder(Object& obj, Planet& target, bool append) {
		addOrder(obj, CaptureOrder(target), append);
		obj.wake();
	}

	void addOddityGateOrder(Object& obj, Oddity& target, bool append) {
		addOrder(obj, OddityGateOrder(target), append);
		obj.wake();
	}

	void addSlipstreamOrder(Object& obj, vec3d pos, bool append) {
		addOrder(obj, SlipstreamOrder(pos), append);
		obj.wake();
	}

	void addSecondaryToSlipstream(Object& other) {
		Order@ last = order;
		while(last.next !is null)
			@last = last.next;
		while(last !is null && last.type != OT_Slipstream)
			@last = last.prev;
		if(last !is null)
			cast<SlipstreamOrder>(last).secondary.insertLast(other);
	}

	void addWaitOrder(Object& obj, Object@ waitingFor, bool append, bool moveTo = false) {
		addOrder(obj, WaitOrder(waitingFor, moveTo), append);
		obj.wake();
	}

	void moveAfterWait(Object& obj, vec3d position, Object@ waitingFor) {
		Order@ ord = order;
		while(ord !is null) {
			if(ord.type == OT_Wait) {
				if(cast<WaitOrder>(ord).waitTarget is waitingFor) {
					quaterniond facing = quaterniond_fromVecToVec(vec3d_front(), position - obj.position);
					MoveOrder move(position, facing);

					if(ord.prev !is null)
						@ord.prev.next = move;
					if(ord.next !is null)
						@ord.next.prev = move;
					if(ord is order)
						@order = move;
					return;
				}
			}
			@ord = ord.next;
		}
	}

	void insertMoveOrder(Object& obj, vec3d pos, uint index) {
		quaterniond facing = quaterniond_fromVecToVec(vec3d_front(), pos - obj.position);
		insertOrder(obj, MoveOrder(pos, facing), index);
		obj.wake();
	}

	void addMoveOrder(Object& obj, vec3d pos, bool append) {
		quaterniond facing = quaterniond_fromVecToVec(vec3d_front(), pos - obj.position);
		addOrder(obj, MoveOrder(pos, facing), append);
		obj.wake();
	}

	void addMoveOrder(Object& obj, vec3d pos, quaterniond facing, bool append) {
		addOrder(obj, MoveOrder(pos, facing), append);
		obj.wake();
	}

	void insertHyperdriveOrder(Object& obj, vec3d pos, uint index) {
		if(!canHyperdrive(obj))
			return;
		insertOrder(obj, HyperdriveOrder(pos), index);
		obj.wake();
	}

	void addHyperdriveOrder(Object& obj, vec3d pos, bool append) {
		if(!canHyperdrive(obj))
			return;
		addOrder(obj, HyperdriveOrder(pos), append);
		obj.wake();
	}

	void insertJumpdriveOrder(Object& obj, vec3d pos, uint index) {
		if(!canJumpdrive(obj))
			return;
		insertOrder(obj, JumpdriveOrder(pos), index);
		obj.wake();
	}

	void addJumpdriveOrder(Object& obj, vec3d pos, bool append) {
		if(!canJumpdrive(obj))
			return;
		addOrder(obj, JumpdriveOrder(pos), append);
		obj.wake();
	}

	void insertFlingOrder(Object& obj, Object& beacon, vec3d pos, uint index) {
		if(obj.owner is null || !obj.owner.isFlingBeacon(beacon) || beacon is obj)
			return;
		insertOrder(obj, FlingOrder(beacon, pos), index);
		obj.wake();
	}

	void addFlingOrder(Object& obj, Object& beacon, vec3d pos, bool append) {
		if(obj.owner is null || !obj.owner.isFlingBeacon(beacon) || beacon is obj)
			return;
		addOrder(obj, FlingOrder(beacon, pos), append);
		obj.wake();
	}

	void addScanOrder(Object& obj, Anomaly& target, bool append) {
		addOrder(obj, ScanOrder(target), append);
		obj.wake();
	}

	void addRefreshOrder(Object& obj, Object& target, bool append) {
		addOrder(obj, RefreshOrder(target), append);
		obj.wake();
	}
	
	void addAutoExploreOrder(Object& obj, bool useFTL, bool append) {
		addOrder(obj, AutoExploreOrder(useFTL), append);
		obj.wake();
	}

	void leaderInit(Object& obj) {
		if(obj.isShip) {
			double formationRad = getFormationRadius(obj);
			@node = FleetPlaneNode();
			node.establish(obj, formationRad);
			node.hintParentObject(obj.region, false);
			node.hasFleet = supports.length > 0;
			node.hasSupply = supplyCapacity > 0;
			engagementRange = 200.0 - formationRad;

			Ship@ ship = cast<Ship>(obj);
			needExperience = ship.blueprint.design.size * config::EXPERIENCE_BASE_AMOUNT;

			const Design@ dsg = ship.blueprint.design;
			if(dsg !is null && !dsg.hasTag(ST_Weapon) && dsg.total(SV_SupportCapacity) > 0)
				engageType = ER_RaidingOnly;
		}
		else {
			needExperience = INFINITY;
		}

		formation.reset(obj.radius * 2.0, getFormationRadius(obj));
		leaderChangeOwner(obj, null, obj.owner);

		AllowFillFrom = obj.isPlanet;
		autoFill = !AllowFillFrom && !obj.isOrbital;

		allowSatellites = obj.isPlanet;
		rememberGhosts = obj.isShip;
		compEngageRange(obj);
	}

	void leaderPostLoad(Object& obj) {
		if(obj.isShip) {
			@node = FleetPlaneNode();
			node.establish(obj, getFormationRadius(obj));
			node.hintParentObject(obj.region, false);
			node.hasSupply = supplyCapacity > 0;
			node.hasFleet = supports.length > 0;
		}

		if(START_VERSION < SV_0073) {
			autoFill = obj.isShip;
			rememberGhosts = obj.isShip;
		}

		for(int i = supports.length - 1; i >= 0; --i) {
			if(supports[i] is null || !supports[i].valid)
				supports.removeAt(i);
		}
	}

	void leaderDestroy(Object& obj) {
		if(registered) {
			if(obj.owner !is null && obj.owner.valid)
				obj.owner.unregisterFleet(obj);
		}
		for(uint i = 0, cnt = supports.length; i < cnt; ++i)
			supports[i].clearLeader(obj);
		supplyUsed = 0;
		supplySatellite = 0;
		supplyCapacity = 0;
		supports.length = 0;
		if(node !is null) {
			cast<Node>(node).markForDeletion();
			@node = null;
		}
		if(prevOrbit !is null)
			prevOrbit.leaveFromOrbit(cast<Ship>(obj));
		clearOrders(obj);
	}
	
	void leaderRegionChanged(Object& obj) {
		if(node !is null)
			node.hintParentObject(obj.region, false);
	}

	void leaderChangeOwner(Object& obj, Empire@ oldOwner, Empire@ newOwner) {
		if(registered) {
			if(oldOwner !is null && oldOwner.valid)
				oldOwner.unregisterFleet(obj);
			if(newOwner !is null && newOwner.valid)
				newOwner.registerFleet(obj);
		}
	}

	void repairFleet(Object& obj, double amount, bool spread = true) {
		double per = amount;
		if(spread)
			per /= double(supports.length + 1);
		Ship@ ship = cast<Ship>(obj);
		if(ship !is null)
			ship.repairShip(per);
		for(uint i = 0, cnt = supports.length; i < cnt; ++i) {
			@ship = cast<Ship>(supports[i]);
			if(ship !is null)
				ship.repairShip(per);
		}
	}
	
	void findTargets(Object& source, array<Object@>& targets, Object& obj, Empire@ emp, int depth = 3, double maxDistSQ = 1.0e6) {
		for(uint i = 0; i < TARGET_COUNT; ++i) {
			auto@ targ = obj.targets[i];
			if(targ.valid && emp.isHostile(targ.owner)) {
				if(targ.position.distanceToSQ(source.position) > maxDistSQ)
					continue;
				switch(targ.type) {
					case OT_Ship: case OT_Orbital:
						targets.insertLast(targ);
						break;
				}
			}
		}
		
		if(depth > 0)
			for(uint i = 0; i < TARGET_COUNT; ++i)
				findTargets(source, targets, obj.targets[i], emp, depth-1, maxDistSQ);
	}

	void findRegionTargets(Region@ region, array<Object@>& targets, Object& obj, Empire@ emp, int depth = 3) {
		for(uint i = 0; i < TARGET_COUNT; ++i) {
			auto@ targ = obj.targets[i];
			if(targ.valid && emp.isHostile(targ.owner)) {
				if(targ.region !is region)
					continue;
				switch(targ.type) {
					case OT_Ship: case OT_Orbital:
						targets.insertLast(targ);
						break;
				}
			}
		}
		
		if(depth > 0)
			for(uint i = 0; i < TARGET_COUNT; ++i)
				findRegionTargets(region, targets, obj.targets[i], emp, depth-1);
	}
	
	
	bool inFleetFight = false;
	Object@ cavalryTarget;
	array<Object@> targs;
	
	void commandTick(Object& obj) {
		if(supports.length == 0)
			return;
	
		targs.length = 0;
		Region@ reg = obj.region;
		if((FreeRaiding || RaidRange < 0) && reg !is null)
			findRegionTargets(reg, targs, obj, obj.owner);
		else if(RaidRange > 0)
			findTargets(obj, targs, obj, obj.owner, maxDistSQ=RaidRange*RaidRange);

		bool engage = obj.inCombat || targs.length > 0;
		/*if(engage && !inFleetFight) {*/
		/*}*/
		/*else if(!engage && inFleetFight) {*/
		/*	standDownAllSupports();*/
		/*}*/
		/*inFleetFight = engage;*/
		
		if(!engage)
			@cavalryTarget = null;
		if(!engage || targs.length == 0)
			return;
		
		if(targs.length > 0) {
			if(cavalryTarget is null || !cavalryTarget.valid) {
				@cavalryTarget = null;

				for(uint i = 0, cnt = targs.length; i < cnt; ++i) {
					auto@ targ = targs[i];
					if(targ.isShip && targ.hasSupportAI) {	
						@cavalryTarget = targ;
						break;
					}
				}
				
				if(cavalryTarget !is null)
					for(uint i = 0, cnt = supports.length; i < cnt; ++i)
						supports[i].cavalryCharge(cavalryTarget);
			}
			
			uint supportCount = supports.length;
			for(uint i = 0, cnt = targs.length; i < cnt; ++i)
				supports[randomi(0, supportCount-1)].supportInterfere(targs[i], obj);
		}
		
		targs.length = 0;
	}

	Planet@ prevOrbit;
	uint chkIndex = 0;
	void leaderTick(Object& obj, double time) {
		//Set plane visibility
		if(node !is null)
			node.visible = obj.isVisibleTo(playerEmpire);

		//Refresh formations
		if(formationDelta && !obj.inCombat) {
			if(!obj.hasMover || !obj.isMoving) {
				double minRad = obj.radius + 2.0;
				double maxRad = getFormationRadius(obj);
				formation.reset(minRad, maxRad);
				for(uint i = 0, cnt = supports.length; i < cnt; ++i) {
					Ship@ ship = cast<Ship>(supports[i]);
					const Design@ dsg = ship.blueprint.design;
					if(dsg !is null && !dsg.hasTag(ST_Satellite))
						ship.formationDest.xyz = formation.getNext(supports[i]);
				}
				formationDelta = false;
			}
			compEngageRange(obj);
		}

		//Register anything that can hold support ships
		if(registered != (supplyCapacity > 0 || obj.isShip)) {
			if(registered) {
				if(obj.owner !is null && obj.owner.valid)
					obj.owner.unregisterFleet(obj);
				registered = false;
			}
			else {
				if(obj.owner !is null && obj.owner.valid)
					obj.owner.registerFleet(obj);
				registered = true;
			}
		}

		//Do capturing
		Ship@ ship = cast<Ship>(obj);
		if(ship !is null) {
			Empire@ myOwner = obj.owner;
			Planet@ orbit;
			if(obj.hasOrbit) {
				@orbit = cast<Planet>(obj.getOrbitingAround());
			}
			else {
				@orbit = cast<Planet>(obj.getLockedOrbit(requireLock = false));
				if(orbit !is null) {
					double range = orbit.OrbitSize * orbit.OrbitSize;
					if(orbit.position.distanceToSQ(ship.position) > range)
						@orbit = null;
				}
			}
			if(orbit !is prevOrbit) {
				if(prevOrbit !is null)
					prevOrbit.leaveFromOrbit(ship);
				if(orbit !is null)
					orbit.enterIntoOrbit(ship);
				@prevOrbit = orbit;
			}
			if(orbit !is null && orbit.owner.isHostile(myOwner))
				obj.engaged = true;
		}

		//Drop supports out of the fleet if we're out of supply
		if(supplyUsed - supplyGhost > supplyCapacity && supports.length != 0) {
			auto@ sup = supports[randomi(0, supports.length-1)];
			unregisterSupport(sup, true);
			sup.clearLeader(obj);
		}

		//Drop any actually dead supports that didn't manage to unregister themselves
		if(supports.length != 0) {
			chkIndex = (chkIndex+1) % supports.length;
			auto@ sup = supports[chkIndex];
			if(!sup.valid)
				unregisterSupport(sup, true);
		}

		//Check for construction capability
		Region@ reg = obj.region;
		if(reg !is null && reg.ShipyardMask | reg.AvailSupportMask & obj.owner.mask != 0) {
			//Handle retrofitting of leader
			if(reg.ContestedMask & obj.owner.mask == 0 && reg.ShipyardMask & obj.owner.mask != 0) {
				if(ship !is null && !ship.inCombat) {
					const Design@ dsg = ship.blueprint.design;
					if(dsg.outdated)
						obj.owner.updateDesign(dsg, true);
					if(dsg.updated !is null)
						ship.retrofit(dsg.mostUpdated());
				}

				//Handle retrofitting of support ships
				if(supports.length != 0) {
					int ind = randomi(0, supports.length - 1);
					for(uint i = 0; i < 10; ++i) {
						Ship@ ship = cast<Ship>(supports[ind]);
						if(ship !is null && !ship.inCombat) {
							const Design@ dsg = ship.blueprint.design;
							if(dsg.outdated)
								obj.owner.updateDesign(dsg, true);
							if(dsg.updated !is null) {
								const Design@ newDesign = dsg.mostUpdated();
								ship.retrofit(newDesign);
							}
						}

						ind = (ind + 1) % supports.length;
					}
				}
			}

			//Handle construction of ordered ships
			constructionTimer -= time;
			if(constructionTimer <= 0 && canGain) {
				Region@ region = obj.region;
				if(region !is null) {
					//Handle new construction orders
					bool haveYard = reg.ShipyardMask & obj.owner.mask != 0;
					bool haveOrdered = false, haveGhosts = false;
					for(uint i = 0, cnt = groupData.length; i < cnt; ++i) {
						GroupData@ dat = groupData[i];
						if(dat.ordered > dat.waiting && haveYard) {
							uint id = nextConstructionId++;
							region.regionBuildSupport(id, obj, dat.dsg);
							constructionTimer += randomd(0.1, min(2.0, dat.dsg.size * 0.3));
						}
						if(dat.ordered > 0 || dat.waiting > 0)
							haveOrdered = true;
						if(dat.ghost > 0)
							haveGhosts = true;
					}

					if(supplyUsed - supplyGhost < supplyCapacity || haveGhosts) {
						//Handle auto-fill
						if(autoFill && region.AvailSupportMask & obj.owner.mask != 0
								&& double(supplyUsed - supplyGhost) < double(supplyCapacity) * 0.95
								&& region.ContestedMask & obj.owner.mask == 0) {
							obj.refreshSupportsFrom(region);
							constructionTimer += 5.0;
						}
						//Handle auto-buy
						if(autoBuy && !haveOrdered) {
							autoBuySupport(obj, maxAmount=1);
							constructionTimer += randomd(0.1, 0.3);
							haveOrdered = true;
						}
					}
				}

				if(constructionTimer <= 0)
					constructionTimer = randomd(0.5, 3.0);
			}
		}
	}

	void postSupportRetrofit(Object& obj, Ship@ support, const Design@ prevDesign, const Design@ newDesign) {
		if(prevDesign.base() is newDesign.base())
			return;

		supplyUsed -= prevDesign.size;
		if(prevDesign.hasTag(ST_Satellite))
			supplySatellite -= prevDesign.size;
		int index = getGroupDataIndex(prevDesign, false);
		if(index != -1) {
			GroupData@ prevDat = groupData[index];
			prevDat.amount -= 1;

			if(prevDat.totalSize <= 0)
				groupData.removeAt(index);
		}

		supplyUsed += newDesign.size;
		if(newDesign.hasTag(ST_Satellite))
			supplySatellite += newDesign.size;
		int newIndex = getGroupDataIndex(newDesign, true);
		GroupData@ newDat = groupData[newIndex];
		newDat.amount += 1;
	}

	void supportBuildStarted(Object& obj, uint id, const Design@ dsg, Object@ shipyard) {
		int ind = getGroupDataIndex(dsg, false);
		if(ind == -1) {
			shipyard.cancelBuildSupport(id);
			return;
		}

		GroupData@ dat = groupData[ind];
		if(dat.ordered <= dat.waiting) {
			shipyard.cancelBuildSupport(id);
			return;
		}

		++dat.waiting;

		//Record that something is being constructed for us
		ActiveConstruction con;
		con.id = id;
		@con.dsg = dsg;
		@con.shipyard = shipyard;

		activeConstructions.insertLast(con);

		delta = true;
	}

	void supportBuildFinished(Object& obj, uint id, const Design@ dsg, Object@ shipyard, Ship@ ship) {
		//Take null shipyards as an 'ordered' decrease.
		if(shipyard is null) {
			int groupIndex = getGroupDataIndex(dsg, false);
			if(groupIndex == -1)
				return;

			GroupData@ dat = groupData[groupIndex];
			if(dat.ordered > 0) {
				--dat.ordered;
				supplyOrdered -= dat.dsg.size;

				orderedHP -= dat.dsg.totalHP;
				orderedDPS -= dat.dsg.total(SV_DPS);
			}
			supplyUsed -= dat.dsg.size;
			if(dat.dsg.hasTag(ST_Satellite))
				supplySatellite -= dat.dsg.size;
			obj.registerSupport(ship);
			return;
		}

		//Find the active construction
		int index = -1;
		for(int i = 0, cnt = int(activeConstructions.length); i < cnt; ++i) {
			ActiveConstruction@ con = activeConstructions[i];
			if(con.id == id) {
				index = i;
				break;
			}
		}

		//We don't know what the hell to do with it
		if(index == -1) {
			ship.destroy();
			return;
		}

		ActiveConstruction@ con = activeConstructions[index];
		int groupIndex = getGroupDataIndex(dsg, false);
		activeConstructions.removeAt(index);

		if(groupIndex == -1) {
			ship.destroy();
			return;
		}

		GroupData@ dat = groupData[groupIndex];
		if(dat.waiting == 0) {
			ship.destroy();
			return;
		}

		if(dat.waiting > dat.ordered || ship.owner !is obj.owner) {
			ship.destroy();
			--dat.waiting;
			return;
		}

		--dat.waiting;
		--dat.ordered;
		obj.owner.modMaintenance(-getMaintenanceCost(dsg), MoT_Ships);
		supplyOrdered -= dat.dsg.size;
		supplyUsed -= dat.dsg.size;
		if(dat.dsg.hasTag(ST_Satellite))
			supplySatellite -= dat.dsg.size;
		orderedHP -= dat.dsg.totalHP;
		orderedDPS -= dat.dsg.total(SV_DPS);
		obj.registerSupport(ship);

		delta = true;
	}

	void orderSupports(Object& obj, const Design@ ofDesign, uint amount) {
		if(!ofDesign.hasTag(ST_IsSupport))
			return;
		if(ofDesign.hasTag(ST_Satellite) && !allowSatellites)
			return;
		amount = min(amount, UINT_MAX / uint(ofDesign.size));
		delta = true;

		int ind = getGroupDataIndex(ofDesign, false);
		uint takeFromGhost = 0;
		if(ind != -1)
			takeFromGhost = min(groupData[ind].ghost, amount);
		
		uint capMax = 0;
		if(supplyCapacity > supplyUsed)
			capMax = (supplyCapacity - supplyUsed) / uint(ofDesign.size);
		
		amount = min(amount, capMax + takeFromGhost);
		if(amount == 0)
			return;

		int cost = getBuildCost(ofDesign, amount);
		int cycle = obj.owner.consumeBudget(cost, true);
		if(cycle == -1)
			return;

		if(ind == -1)
			ind = getGroupDataIndex(ofDesign, true);
		GroupData@ dat = groupData[ind];
		dat.ordered += amount;
		supplyOrdered += amount * dat.dsg.size;
		orderedHP += double(amount) * dat.dsg.totalHP;
		orderedDPS += double(amount) * dat.dsg.total(SV_DPS);
		obj.owner.modMaintenance(getMaintenanceCost(ofDesign, amount), MoT_Ships);
		dat.ghost -= takeFromGhost;
		supplyUsed += (amount - takeFromGhost) * ofDesign.size;
		if(ofDesign.hasTag(ST_Satellite))
			supplySatellite += (amount - takeFromGhost) * ofDesign.size;

		ghostHP -= double(takeFromGhost) * ofDesign.totalHP;
		ghostDPS -= double(takeFromGhost) * ofDesign.total(SV_DPS);
		supplyGhost -= takeFromGhost * ofDesign.size;

		if(dat.orderCycle == cycle) {
			dat.orderAmount += amount;
		}
		else {
			dat.orderCycle = cycle;
			dat.orderAmount = amount;
		}
	}

	void autoBuySupport(Object& obj, uint maxAmount = 1) {
		Empire@ owner = obj.owner;
		if(owner is null || !owner.valid || owner.RemainingBudget < 100)
			return;
		int remainSupply = supplyCapacity - supplyUsed;
		while(maxAmount > 0 && remainSupply > 0) {
			bool builtGhost = false;
			uint index = randomi(0, groupData.length-1);
			for(uint i = 0, cnt = groupData.length; i < cnt; ++i) {
				auto@ dat = groupData[i];
				if(dat.ghost > 0) {
					orderSupports(obj, dat.dsg, 1);
					remainSupply -= dat.dsg.size;
					builtGhost = true;
					break;
				}
				index = (index+1) % cnt;
			}

			if(!builtGhost) {
				array<const Design@> designs;
				array<double> weights;
				designs.reserve(16);
				weights.reserve(16);
				double totalWeight = 0.0;

				double optMin = double(remainSupply) / 200.0, optMax = double(remainSupply) / 10.0;
				uint designCount = owner.designCount;
				ReadLock lock(owner.designMutex);
				for(uint i = 0; i < designCount; ++i) {
					const Design@ dsg = owner.designs[i];
					if(dsg.obsolete)
						continue;
					if(dsg.newest() !is dsg)
						continue;
					if(!dsg.hasTag(ST_Support))
						continue;
					if(dsg.size > remainSupply)
						continue;

					double weight = 10.0;
					weight += dsg.built * dsg.size;

					if(dsg.size < optMin)
						weight *= pow(0.5, optMin / dsg.size);
					else if(dsg.size > optMax)
						weight *= pow(0.5, dsg.size / optMax);

					designs.insertLast(dsg);
					weights.insertLast(weight);

					totalWeight += weight;
				}

				double cur = randomd(0.0, totalWeight);
				for(uint i = 0, cnt = designs.length; i < cnt; ++i) {
					const Design@ dsg = designs[i];
					cur -= weights[i];

					if(cur <= 0) {
						orderSupports(obj, dsg, 1);
						break;
					}
				}
			}

			--maxAmount;
		}
	}

	int rebuildGhostsCost(Object& obj) {
		int cost = 0;
		for(uint i = 0, cnt = groupData.length; i < cnt; ++i) {
			GroupData@ data = groupData[i];
			if(data.ghost > 0)
				cost += data.ghost * getBuildCost(data.dsg);
		}
		return cost;
	}
	
	void rebuildAllGhosts(Object& obj) {
		for(uint i = 0, cnt = groupData.length; i < cnt; ++i) {
			GroupData@ data = groupData[i];
			if(data.ghost > 0)
				orderSupports(obj, data.dsg, data.ghost);
		}
	}

	void clearAllGhosts(Object& obj) {
		for(uint i = 0, cnt = groupData.length; i < cnt; ++i) {
			GroupData@ dat = groupData[i];
			if(dat.ghost > 0) {
				supplyUsed -= dat.ghost * dat.dsg.size;
				if(dat.dsg.hasTag(ST_Satellite))
					supplySatellite -= dat.ghost * dat.dsg.size;
				ghostHP -= double(dat.ghost) * dat.dsg.totalHP;
				ghostDPS -= double(dat.ghost) * dat.dsg.total(SV_DPS);
				supplyGhost -= dat.ghost * dat.dsg.size;
				dat.ghost = 0;
				delta = true;
			}
		}
	}

	void scuttleSupports(Object& obj, const Design@ ofDesign, uint amount) {
		@ofDesign = ofDesign.mostUpdated();

		int ind = getGroupDataIndex(ofDesign, false);
		if(ind == -1)
			return;
		GroupData@ dat = groupData[ind];

		//Remove ghosts
		uint take = min(amount, dat.ghost);
		if(take != 0) {
			dat.ghost -= take;
			amount -= take;
			supplyUsed -= take * ofDesign.size;
			if(ofDesign.hasTag(ST_Satellite))
				supplySatellite -= take * ofDesign.size;

			ghostHP -= double(take) * ofDesign.totalHP;
			ghostDPS -= double(take) * ofDesign.total(SV_DPS);
			supplyGhost -= dat.ghost * ofDesign.size;
		}

		//Remove ordered
		take = min(amount, dat.ordered);
		if(take != 0) {
			dat.ordered -= take;
			amount -= take;
			supplyUsed -= take * ofDesign.size;
			if(ofDesign.hasTag(ST_Satellite))
				supplySatellite -= take * ofDesign.size;
			supplyOrdered -= take * ofDesign.size;
			orderedHP -= double(take) * ofDesign.totalHP;
			orderedDPS -= double(take) * ofDesign.total(SV_DPS);
			obj.owner.modMaintenance(-getMaintenanceCost(ofDesign, take), MoT_Ships);

			//Refund if possible
			uint refund = min(dat.orderAmount, take);
			if(refund != 0) {
				int cost = getBuildCost(ofDesign, refund);
				obj.owner.refundBudget(cost, dat.orderCycle);
				dat.orderAmount -= refund;
			}
		}

		//Cancel excess waiting ships
		for(uint i = 0, cnt = activeConstructions.length;
				i < cnt && dat.waiting > dat.ordered && dat.waiting > 0; ++i) {

			ActiveConstruction@ con = activeConstructions[i];
			if(con.dsg !is ofDesign)
				continue;

			con.shipyard.cancelBuildSupport(con.id);
			activeConstructions.removeAt(i);
			--i; --cnt;

			--dat.waiting;
		}

		//Remove group data if it's empty
		if(dat.totalSize <= 0) {
			groupData.removeAt(ind);
			return;
		}

		//Scuttle existing ships
		for(uint i = 0, cnt = supports.length; i < cnt && amount > 0; ++i) {
			Ship@ ship = cast<Ship>(supports[i]);
			if(ship is null)
				continue;
			const Design@ dsg = ship.blueprint.design;
			if(dsg.mostUpdated() is ofDesign) {
				--amount;
				ship.supportScuttle();
				if(supports.length != cnt) {
					--cnt;
					--i;
				}
			}
		}

		delta = true;
	}

	void convertRandomSupport(Object@ toLeader, Empire@ toEmpire, int maxSize) {
		uint offset = randomi(0, supports.length-1);
		for(uint i = 0, cnt = supports.length; i < cnt; ++i) {
			Ship@ sup = cast<Ship>(supports[(i+offset) % cnt]);
			int sz = sup.blueprint.design.size;
			if(maxSize > 0 && sz > maxSize)
				continue;

			@sup.owner = toEmpire;
			if(toLeader !is null)
				sup.transferTo(toLeader);
			break;
		}
	}

	double getFormationRadius(Object& obj) {
		Planet@ pl = cast<Planet>(obj);
		if(pl !is null)
			return pl.OrbitSize;
		return obj.radius * 10.0 + 20.0;
	}
	
	double get_slowestSupportAccel() const {
		double slowest = 0.0;
		
		for(uint i = 0, cnt = groupData.length; i < cnt; ++i) {
			GroupData@ dat = groupData[i];
			if(dat.amount == 0)
				continue;
			
			auto design = dat.dsg;
			
			double mass = max(design.total(HV_Mass), 0.01f);
			double accel = design.total(SV_Thrust) / mass;
			if((accel < slowest || slowest == 0) && accel > 0.0)
				slowest = accel;
		}
		
		return slowest;
	}

	void modSupplyCapacity(int amt) {
		supplyCapacity += amt;
		delta = true;
		if(node !is null)
			node.hasSupply = supplyCapacity > 0;
	}

	int getGroupDataIndex(const Design@ dsg, bool create = true) {
		@dsg = dsg.mostUpdated();
		for(uint i = 0, cnt = groupData.length; i < cnt; ++i) {
			GroupData@ dat = groupData[i];
			const Design@ oldDesign = dat.dsg;
			const Design@ newDesign = dat.dsg.mostUpdated();
			if(newDesign is dsg.mostUpdated()) {
				if(oldDesign !is newDesign && (dat.ghost > 0 || dat.ordered > 0)) {
					double hpDiff = newDesign.totalHP - oldDesign.totalHP;
					double dpsDiff = newDesign.total(SV_DPS) - oldDesign.total(SV_DPS);
					double sizeDiff = newDesign.size - oldDesign.size;

					if(dat.ghost > 0) {
						ghostHP += double(dat.ghost) * hpDiff;
						ghostDPS += double(dat.ghost) * dpsDiff;
						supplyGhost += double(dat.ghost) * sizeDiff;
						supplyUsed += double(dat.ghost) * sizeDiff;
						if(oldDesign.hasTag(ST_Satellite))
							supplySatellite += double(dat.ghost) * sizeDiff;
					}
					if(dat.ordered > 0) {
						supplyOrdered += double(dat.ordered) * sizeDiff;
						orderedHP += double(dat.ordered) * hpDiff;
						orderedDPS += double(dat.ordered) * dpsDiff;
						supplyUsed += double(dat.ordered) * sizeDiff;
						if(oldDesign.hasTag(ST_Satellite))
							supplySatellite += double(dat.ordered) * sizeDiff;
					}

					@dat.dsg = newDesign;
				}
				return i;
			}
		}
		if(create) {
			GroupData dat;
			@dat.dsg = dsg.mostUpdated();

			groupData.insertLast(dat);
			return groupData.length - 1;
		}
		return -1;
	}

	void getSupportGroups() const {
		for(uint i = 0, cnt = groupData.length; i < cnt; ++i)
			yield(groupData[i]);
	}

	void transferSupports(const Design@ ofDesign, uint amount, Object@ transferTo) {
		if(!transferTo.hasLeaderAI || ofDesign is null || amount == 0)
			return;
		if(ofDesign.hasTag(ST_Satellite))
			return;
		@ofDesign = ofDesign.mostUpdated();

		int ind = getGroupDataIndex(ofDesign, false);
		if(ind == -1)
			return;
		delta = true;

		//Don't try to transfer over our supply cap
		amount = min(amount, transferTo.SupplyAvailable / uint(ofDesign.size));
		if(amount == 0)
			return;

		//Transfer real ships over first
		for(uint i = 0, cnt = supports.length; i < cnt; ++i) {
			Ship@ ship = cast<Ship>(supports[i]);
			if(ship is null)
				continue;
			const Design@ dsg = ship.blueprint.design;
			if(dsg.mostUpdated() is ofDesign) {
				--amount;

				//Transfer the ship away,
				//can either happen right now
				//or at some later point
				ship.transferTo(transferTo);

				//Ship was removed right now,
				//so make sure we loop correctly
				if(supports.length != cnt) {
					--cnt;
					--i;
				}

				if(amount == 0)
					break;
			}
		}

		ind = getGroupDataIndex(ofDesign, false);
		if(ind == -1)
			return;
		GroupData@ dat = groupData[ind];

		//Transfer ordered
		if(amount == 0)
			return;

		uint take = min(dat.ordered, amount);
		if(take != 0) {
			amount -= take;
			dat.ordered -= take;
			supplyOrdered -= take * ofDesign.size;
			supplyUsed -= take * ofDesign.size;
			if(ofDesign.hasTag(ST_Satellite))
				supplySatellite -= take * ofDesign.size;
			orderedHP -= double(take) * ofDesign.totalHP;
			orderedDPS -= double(take) * ofDesign.total(SV_DPS);
			transferTo.addSupportOrdered(ofDesign, take);

			dat.orderCycle = -1;
			dat.orderAmount = 0;
		}

		if(dat.totalSize <= 0)
			groupData.removeAt(ind);

		//Transfer ghosts
		if(amount == 0)
			return;

		take = min(dat.ghost, amount);
		if(take != 0) {
			dat.ghost -= take;
			amount -= take;
			supplyUsed -= take * ofDesign.size;
			if(ofDesign.hasTag(ST_Satellite))
				supplySatellite -= take * ofDesign.size;
			transferTo.addSupportGhosts(ofDesign, take);

			ghostHP -= double(take) * ofDesign.totalHP;
			ghostDPS -= double(take) * ofDesign.total(SV_DPS);
			supplyGhost -= take * ofDesign.size;
		}

		if(dat.totalSize <= 0) {
			groupData.removeAt(ind);
			return;
		}

		//Cancel excess waiting ships
		for(uint i = 0, cnt = activeConstructions.length;
				i < cnt && dat.waiting > dat.ordered && dat.waiting > 0; ++i) {

			ActiveConstruction@ con = activeConstructions[i];
			if(con.dsg.mostUpdated() !is ofDesign)
				continue;

			con.shipyard.cancelBuildSupport(con.id);
			activeConstructions.removeAt(i);
			--i; --cnt;

			--dat.waiting;
		}
	}

	double getEngagementRange() {
		return engagementRange;
	}

	bool get_freeRaiding() {
		return FreeRaiding;
	}

	double get_raidRange() {
		return RaidRange;
	}

	void setFreeRaiding(bool value) {
		FreeRaiding = value;
	}

	void modRaidRange(double value) {
		RaidRange += value;
		if(engageType == ER_RaidingOnly)
			engagementRange = RaidRange;
	}

	Object@ getAttackTarget() {
		AttackOrder@ ao = cast<AttackOrder>(order);
		if(ao is null)
			return null;
		return ao.target;
	}

	double getAttackDistance(Object& obj) {
		AttackOrder@ ao = cast<AttackOrder>(order);
		if(ao is null || ao.target is null)
			return -1.0;
		return obj.position.distanceTo(ao.target.position);
	}

	void addSupportGhosts(Object& obj, const Design@ ofDesign, uint amount) {
		int ind = getGroupDataIndex(ofDesign, true);
		GroupData@ dat = groupData[ind];
		dat.ghost += amount;
		supplyUsed += amount * ofDesign.size;
		if(ofDesign.hasTag(ST_Satellite))
			supplySatellite += amount * ofDesign.size;

		ghostHP += double(amount) * ofDesign.totalHP;
		ghostDPS += double(amount) * ofDesign.total(SV_DPS);
		supplyGhost += amount * ofDesign.size;

		delta = true;
	}

	void addSupportOrdered(Object& obj, const Design@ ofDesign, uint amount) {
		int ind = getGroupDataIndex(ofDesign, true);
		GroupData@ dat = groupData[ind];
		dat.ordered += amount;
		supplyOrdered += amount * ofDesign.size;
		supplyUsed += amount * ofDesign.size;
		if(ofDesign.hasTag(ST_Satellite))
			supplySatellite += amount * ofDesign.size;
		orderedHP += double(amount) * ofDesign.totalHP;
		orderedDPS += double(amount) * ofDesign.total(SV_DPS);

		delta = true;
	}

	void registerSupport(Object& obj, Object@ support, bool pickup, bool force) {
		if(!obj.valid || !support.valid || (!canGain && !force))
			return;

		Ship@ othership = cast<Ship>(support);
		if(othership !is null) {
			othership.supportIdle();
		
			const Design@ dsg = othership.blueprint.design;
			int ind = getGroupDataIndex(dsg, false);
			bool canGhost = false;
			if(ind != -1)
				canGhost = pickup && groupData[ind].ghost > 0;

			uint supply = dsg.size;
			if(!canGhost && supplyUsed + supply > supplyCapacity)
				return;

			supplyUsed += supply;
			if(dsg.hasTag(ST_Satellite))
				supplySatellite += supply;

			double minRad = obj.radius + 2.0;
			double maxRad = getFormationRadius(obj);

			/*double height = randomd(-1.0,1.0) * support.radius;*/
			/*vec2d rand = random2d(minRad, sqrt(maxRad*maxRad - height*height));*/
			/*othership.formationDest.xyz = vec3d(rand.x, height, rand.y);*/

			if(dsg.hasTag(ST_Satellite))
				othership.formationDest.xyz = (othership.position - obj.position);
			else
				othership.formationDest.xyz = formation.getNext(othership);

			//Add to group data count
			if(ind == -1)
				ind = getGroupDataIndex(dsg, true);
			GroupData@ dat = groupData[ind];
			++dat.amount;

			if(canGhost) {
				--dat.ghost;
				supplyUsed -= dsg.size;
				if(dsg.hasTag(ST_Satellite))
					supplySatellite -= dsg.size;

				ghostHP -= dsg.totalHP;
				ghostDPS -= dsg.total(SV_DPS);
				supplyGhost -= dsg.size;
			}
		}

		supports.insertLast(support);
		support.completeRegisterLeader(obj);

		if(node !is null && supports.length == 1)
			node.hasFleet = true;

		addEngageRange(obj, support);

		if(mpServer) {
			delta = true;
			if(addedSupports is null)
				@addedSupports = array<Object@>();
			addedSupports.insertLast(support);
			if(removedSupports !is null)
				removedSupports.remove(support);
		}
	}

	void unregisterSupport(Object@ support, bool destroyed) {
		int index = supports.find(support);
		if(index == -1)
			return;

		supports.removeAt(index);
		Ship@ othership = cast<Ship>(support);
		if(othership !is null) {
			const Design@ design = othership.blueprint.design;
			supplyUsed -= design.size;
			if(design.hasTag(ST_Satellite))
				supplySatellite -= design.size;

			int index = getGroupDataIndex(design, false);
			if(index != -1) {
				GroupData@ dat = groupData[index];
				--dat.amount;
				if(destroyed && rememberGhosts) {
					++dat.ghost;
					supplyUsed += design.size;
					if(design.hasTag(ST_Satellite))
						supplySatellite += design.size;

					ghostHP += design.totalHP;
					ghostDPS += design.total(SV_DPS);
					supplyGhost += design.size;
				}
				if(dat.totalSize <= 0)
					groupData.removeAt(index);
			}
		}

		if(node !is null && supports.length == 0)
			node.hasFleet = false;

		formationDelta = true;

		if(mpServer) {
			delta = true;
			if(removedSupports is null)
				@removedSupports = array<Object@>();
			removedSupports.insertLast(support);
			if(addedSupports !is null)
				addedSupports.remove(support);
		}
	}

	void teleportTo(Object& obj, vec3d position, bool movementPart) {
		vec3d oldPos = obj.position;
		obj.position = position;
		obj.velocity = vec3d();
		obj.acceleration = vec3d();
		bool combat = obj.inCombat;

		for(uint i = 0, cnt = supports.length; i < cnt; ++i) {
			Object@ sup = supports[i];
			if(!sup.valid)
				continue;
			vec3d posDiff = sup.position - oldPos;
			sup.position = position + posDiff;
			sup.velocity = vec3d();
			sup.acceleration = vec3d();
			sup.flagPositionUpdate();
			if(combat)
				sup.supportIdle();
		}

		if(obj.hasMover) {
			if(!movementPart)
				obj.addMoveOrder(position);
			obj.flagPositionUpdate();
		}
	}

	void refreshSupportsFrom(Object& obj, Object@ from, bool keepGhosts = false) {
		array<Object@> sources;
		if(from.hasLeaderAI) {
			sources.insertLast(from);
		}
		else if(from.isRegion) {
			cast<Region>(from).refreshSupportsFor(obj, keepGhosts);
			return;
		}

		uint sourceCnt = sources.length;
		if(sourceCnt == 0)
			return;

		//Try to refresh ghosts first
		bool done = false;
		while(!done) {
			done = true;
			uint cnt = groupData.length;
			for(uint i = 0; i < cnt; ++i) {
				GroupData@ dat = groupData[i];
				if(dat.dsg.hasTag(ST_Satellite))
					continue;
				if(dat.ghost > 0) {
					uint need = dat.ghost;
					if(!keepGhosts) {
						dat.ghost = 0;
						supplyUsed -= need * dat.dsg.size;
						ghostHP -= double(need) * dat.dsg.totalHP;
						ghostDPS -= double(need) * dat.dsg.total(SV_DPS);
						supplyGhost -= need * dat.dsg.size;
					}

					for(uint n = 0; n < sourceCnt && need > 0; ++n) {
						Object@ source = sources[n];
						uint amt = source.getSupportCount(dat.dsg);
						if(amt > 0) {
							amt = min(amt, need);
							if(keepGhosts) {
								supplyUsed -= amt * dat.dsg.size;
								ghostHP -= double(amt) * dat.dsg.totalHP;
								ghostDPS -= double(amt) * dat.dsg.total(SV_DPS);
								supplyGhost -= amt * dat.dsg.size;
							}
							source.transferSupports(dat.dsg, amt, obj);
							need -= amt;
						}
					}

					done = false;
					break;
				}
			}
		}

		//Fill up the rest of the fleet with whatever is available
		uint supplyLeft = 0;
		if(supplyCapacity > supplyUsed)
			supplyLeft = supplyCapacity - supplyUsed;

		array<GroupData> otherData;
		for(uint n = 0; n < sourceCnt && supplyLeft > 0; ++n) {
			Object@ source = sources[n];
			otherData.syncFrom(source.getSupportGroups());

			for(uint j = 0, jcnt = otherData.length; j < jcnt && supplyLeft > 0; ++j) {
				GroupData@ dat = otherData[j];
				if(dat.dsg.hasTag(ST_Satellite))
					continue;
				uint sup = uint(dat.dsg.size);
				uint amt = min(dat.amount, supplyLeft / sup);
				if(amt > 0) {
					supplyLeft -= amt * sup;
					source.transferSupports(dat.dsg, amt, obj);
				}
			}
		}
	}

	void writeOrders(const Object& obj, Message& msg) {
		msg.writeAlign();
		uint cntPos = msg.reserve();
		uint cnt = 0;
		Order@ ord = @order;
		while(ord !is null) {
			ord.writeDesc(obj, msg);
			@ord = ord.next;
			++cnt;
		}
		msg.fill(cntPos, cnt);

		msg.writeSmall(uint(autoMode));
		msg.writeSmall(uint(engageType));
		msg.writeSmall(uint(engageBehave));
		msg << autoFill << autoBuy << AllowFillFrom;
	}

	void writeLeaderData(Message& msg) {
		uint cnt = groupData.length;
		msg.writeSmall(cnt);
		for(uint i = 0; i < cnt; ++i)
			msg << groupData[i];

		msg.writeSmall(supplyCapacity);
		msg.writeSmall(supplyUsed);
		if(fleetEffectiveness != 1.f) {
			msg.write1();
			msg.writeFixed(fleetEffectiveness, 0.f, 50.f, 16);
		}
		else {
			msg.write0();
		}
		if(permanentEffectiveness != 0.f) {
			msg.write1();
			msg.writeFixed(permanentEffectiveness, 0.f, 50.f, 16);
		}
		else {
			msg.write0();
		}
		if(bonusDPS != 0.f) {
			msg.write1();
			msg << float(bonusDPS);
		}
		else {
			msg.write0();
		}

		if(needExperience != 0.f) {
			msg.write1();
			msg << float(needExperience);
		}
		else {
			msg.write0();
		}
	}

	void writeGroup(Message& msg) {
		uint cnt = supports.length;
		msg.writeSmall(cnt);
		for(uint i = 0; i < cnt; ++i)
			msg << supports[i];

		writeLeaderData(msg);
	}

	void writeGroupDelta(Message& msg) {
		if(addedSupports !is null && addedSupports.length != 0) {
			msg.write1();
			msg.writeSmall(addedSupports.length);
			for(uint i = 0, cnt = addedSupports.length; i < cnt; ++i)
				msg << addedSupports[i];
			addedSupports.length = 0;
		}
		else {
			msg.write0();
		}
		if(removedSupports !is null && removedSupports.length != 0) {
			msg.write1();
			msg.writeSmall(removedSupports.length);
			for(uint i = 0, cnt = removedSupports.length; i < cnt; ++i)
				msg << removedSupports[i];
			removedSupports.length = 0;
		}
		else {
			msg.write0();
		}

		writeLeaderData(msg);
	}

	void writeLeaderAI(const Object& obj, Message& msg) {
		writeGroup(msg);
		writeOrders(obj, msg);
		msg << allowSatellites;
	}

	bool writeLeaderAIDelta(const Object& obj, Message& msg) {
		if(!delta && !orderDelta)
			return false;
		msg.write1();

		if(delta) {
			msg.write1();
			writeGroupDelta(msg);
			delta = false;
		}
		else {
			msg.write0();
		}

		if(orderDelta) {
			msg.write1();
			writeOrders(obj, msg);
			orderDelta = false;
		}
		else {
			msg.write0();
		}

		return true;
	}
};

tidy class IntersperseFormation : Formation, Savable {
	double minRad, maxRad;
	double angle, step;
	double radius, start;
	int outer;
	bool sign;

	void save(SaveFile& file) {
		file << minRad << maxRad;
		file << angle << step;
		file << radius << start;
		file << outer << sign;
	}

	void load(SaveFile& file) {
		file >> minRad >> maxRad;
		file >> angle >> step;
		file >> radius >> start;
		file >> outer >> sign;
	}

	void reset(double minRad, double maxRad) {
		this.minRad = minRad;
		this.maxRad = maxRad;
		radius = minRad * 1.5;
		sign = false;

		step = twopi / (radius / (maxRad / 25.0));
		angle = 0.0;
		outer = 0;
		start = 0.0;
	}

	vec3d getNext(Object& support) {
		quaterniond rot = quaterniond_fromAxisAngle(vec3d_up(), start + (sign ? angle : -angle));
		vec3d pos = rot * (vec3d_front() * radius);

		//Deal with the tilt of additional discs
		if(outer != 0) {
			double tilt = (double(outer / 2) + randomd(0.6,1.4)) * (pi / 15.0);
			if(outer % 2 == 0)
				tilt = -tilt;
			if(tilt > pi)
				return random3d(minRad, maxRad);
			rot = quaterniond_fromAxisAngle(vec3d_right(), tilt);
			pos = rot * pos;
		}

		//Deal with the next step
		if(!sign)
			angle += step;
		sign = !sign;
		if(angle > pi) {
			radius += randomd(8.0,12.0);
			sign = false;
			if(radius >= maxRad) {
				outer += 1;
				radius = minRad * randomd(1.2, 1.4);
				step = twopi / (radius / (maxRad / 25.0));
				start = randomd(0.0, pi);
				angle = 0.0;
			}
			else {
				step = twopi / (radius / (maxRad / 25.0));
				angle = 0.0;
			}
		}

		//Deal with height variation
		pos.y += randomd(-1.0,1.0) * support.radius;

		return pos;
	}
};

int levelStatus = -1;
void init() {
	levelStatus = getStatusID("ShipLevel");
}
