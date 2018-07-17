import biomes;
import resources;
import systems;
import planets.PlanetSurface;
import planet_levels;
import bool getCheatsEverOn() from "cheats";

const double COLONYSHIP_BASE_ACCEL = 5.5;

tidy class SurfaceComponent : Component_SurfaceComponent {
	uint biome0, biome1, biome2;
	vec2u originalSurfaceSize;
	double Population = 0.0;
	int MaxPopulation = 0;
	int Income = 0;
	bool needsPopulationForLevel = true;

	PlanetIconNode@ icon;
	array<int> iconMemory(getEmpireCount(), -1);
	Object@[] colonization;
	double colonyshipAccel = 1.0;

	uint Level = 0;
	uint LevelChainId = 0;
	uint ResourceLevel = 0;
	uint ColonizingMask = 0;
	uint protectedFromMask = 0;
	int maxPlanetLevel = -1;
	uint orbitsMask = 0;

	uint DecayLevel = 0;
	double DecayTimer = -1.0;

	int Quarantined = 0;
	int Contestion = 0;

	double tileDevelopRate = 1.0;
	double bldConstructRate = 1.0;
	double undevelopedMaint = 1.0;
	bool isSendingColonizers = false;
	bool wasMoving = false;

	uint ResourceModID = 0;
	int BaseLoyalty = 10;
	int LoyaltyBonus = 0;
	bool disableProtection = false;
	double[] LoyaltyEffect = double[](getEmpireCount(), 0);
	double growthRate = 1.0;
	uint gfxFlags = 0;

	array<uint> affinities;
	PlanetSurface grid;

	uint SurfaceModId = 0;

	SurfaceComponent() {
	}

	uint get_planetGraphicsFlags() const {
		return gfxFlags;
	}

	uint get_Biome0() {
		return biome0;
	}

	uint get_Biome1() {
		return biome1;
	}

	uint get_Biome2() {
		return biome2;
	}
	
	uint get_maxPopulation() const {
		return MaxPopulation;
	}

	double get_population() const {
		return Population;
	}

	uint get_level() {
		return Level;
	}

	uint get_levelChain() {
		return LevelChainId;
	}

	int get_maxLevel() {
		return maxPlanetLevel;
	}

	uint get_resourceLevel() {
		return ResourceLevel;
	}

	int get_income() const {
		return Income;
	}

	double get_decayTime() const {
		return DecayTimer;
	}

	bool get_quarantined() const {
		return Quarantined != 0;
	}

	double get_undevelopedMaintenance() const {
		return undevelopedMaint;
	}

	double get_buildingConstructRate() const {
		return bldConstructRate;
	}

	double get_tileDevelopmentRate() const {
		return tileDevelopRate;
	}

	int get_buildingMaintenance() const {
		return grid.Maintenance;
	}

	uint get_pressureCap() const {
		return grid.pressureCap;
	}

	float get_totalPressure() const {
		return grid.totalPressure;
	}

	vec3d get_planetIconPosition(const Object& obj) const {
		if(icon is null)
			return obj.position;
		return icon.position;
	}

	uint get_visibleLevel(Player& pl, const Object& obj) const {
		Empire@ emp = pl.emp;
		if(emp is null)
			return 0;
		if(obj.isVisibleTo(emp))
			return Level;
		if(obj.isKnownTo(emp) && emp.valid)
			return iconMemory[emp.index] & 0xff;
		return 0;
	}

	Empire@ get_visibleOwner(Player& pl, const Object& obj) const {
		Empire@ emp = pl.emp;
		if(emp is null)
			return defaultEmpire;
		if(obj.isVisibleTo(emp))
			return obj.owner;
		if(obj.isKnownTo(emp) && emp.valid) {
			Empire@ other = getEmpireByID((iconMemory[emp.index] & 0xff00) >> 8);
			if(other is null)
				return defaultEmpire;
			return other;
		}
		return defaultEmpire;
	}

	uint getBuildingCount(uint buildingId) const {
		uint amount = 0;
		for(uint i = 0, cnt = grid.buildings.length; i < cnt; ++i) {
			if(grid.buildings[i].type.id == buildingId)
				amount += 1;
		}
		return amount;
	}

	uint getBuildingCount() const {
		return grid.buildings.length;
	}

	uint get_buildingType(uint index) const {
		if(index >= grid.buildings.length)
			return uint(-1);
		return grid.buildings[index].type.id;
	}

	bool isProtected(const Object& obj, Empire@ siegeEmp = null) const {
		if(disableProtection)
			return false;
		if(siegeEmp !is null && protectedFromMask & siegeEmp.mask != 0)
			return true;
		const Region@ region = obj.region;
		if(region !is null) {
			Empire@ owner = obj.owner;
			if(region.ProtectedMask & owner.mask != 0) {
				if(disableProtection)
					return false;
				return true;
			}
		}
		return false;
	}

	int get_baseLoyalty(const Object& obj) const {
		return BaseLoyalty + obj.owner.GlobalLoyalty.value;
	}

	bool get_isBeingColonized(Player& pl, const Object& obj) {
		Empire@ emp = pl.emp;
		if(emp is null)
			return false;
		return ColonizingMask & emp.mask != 0;
	}

	Empire@ get_captureEmpire(const Object& obj) const {
		double best = 0;
		Empire@ bestEmp;
		uint owner = obj.owner.index;
		for(uint i = 0, cnt = LoyaltyEffect.length; i < cnt; ++i) {
			if(LoyaltyEffect[i] < best && i != owner) {
				best = LoyaltyEffect[i];
				@bestEmp = getEmpire(i);
			}
		}
		return bestEmp;
	}

	float get_capturePct(const Object& obj) const {
		double baseLoy = double(BaseLoyalty + obj.owner.GlobalLoyalty.value);
		if(baseLoy == 0)
			return 1.f;
		float best = 0;
		uint owner = obj.owner.index;
		for(uint i = 0, cnt = LoyaltyEffect.length; i < cnt; ++i) {
			if(i != owner) {
				float pct = (-LoyaltyEffect[i]) / baseLoy;
				if(pct > best)
					best = pct;
			}
		}
		return best;
	}

	int get_lowestLoyalty(const Object& obj) const {
		int global = obj.owner.GlobalLoyalty.value;
		int lowest = BaseLoyalty + global;
		for(uint i = 0, cnt = LoyaltyEffect.length; i < cnt; ++i) {
			Empire@ emp = getEmpire(i);
			if(!emp.major || emp is obj.owner)
				continue;
			int loy = BaseLoyalty + global + ceil(LoyaltyEffect[i]);
			if(loy < lowest)
				lowest = loy;
		}
		return lowest;
	}

	int get_currentLoyalty(Player& requestor, const Object& obj) const {
		Empire@ emp = requestor.emp;
		if(emp is null || !emp.valid)
			return BaseLoyalty + obj.owner.GlobalLoyalty.value;
		if(emp is obj.owner)
			return get_lowestLoyalty(obj);
		return BaseLoyalty + obj.owner.GlobalLoyalty.value + ceil(LoyaltyEffect[emp.index]);
	}

	int getLoyaltyFacing(Player& requestor, const Object& obj, Empire@ emp) const {
		Empire@ reqEmp = requestor.emp;
		if(requestor != SERVER_PLAYER && reqEmp !is emp && emp !is obj.owner)
			return BaseLoyalty + obj.owner.GlobalLoyalty.value;
		if(!emp.valid)
			return BaseLoyalty + obj.owner.GlobalLoyalty.value;
		return max(BaseLoyalty + obj.owner.GlobalLoyalty.value + int(ceil(LoyaltyEffect[emp.index])), 0);
	}

	bool get_hasContestion() {
		return Contestion > 0;
	}

	bool get_isContested(const Object& obj) const {
		int cont = Contestion;
		if(cont > 0)
			return true;

		Empire@ owner = obj.owner;
		Region@ reg = obj.region;
		if(reg !is null) {
			if(reg.ContestedMask & owner.mask != 0)
				return true;
		}
		return false;
	}

	bool get_isUnderSiege(const Object& obj) const {
		bool haveSiege = false;
		for(uint i = 0, cnt = LoyaltyEffect.length; i < cnt; ++i) {
			if(LoyaltyEffect[i] < -0.01) {
				haveSiege = true;
				break;
			}
		}
		if(orbitsMask & obj.owner.hostileMask != 0)
			return haveSiege;
		return false;
	}

	bool get_isOverPressure() const {
		return grid.totalPressure > int(grid.pressureCap);
	}

	void getPlanetSurface() {
		yield(grid);
	}
	
	double get_colonyShipAccel(const Object& obj) {
		return colonyshipAccel * COLONYSHIP_BASE_ACCEL * obj.owner.ModSpeed.value * obj.owner.ColonizerSpeed;
	}

	bool get_isColonizing() const {
		return colonization.length != 0;
	}

	bool get_canSafelyColonize(const Object& obj) const {
		if(Level < 1)
			return false;

		auto@ lv = getPlanetLevel(LevelChainId, ResourceLevel);

		//Calculate growth rate
		double growthFactor = growthRate;
		float debtFactor = obj.owner.DebtFactor;
		for(; debtFactor > 0; debtFactor -= 1.f)
			growthFactor *= 0.33f + 0.67f * (1.f - min(debtFactor, 1.f));
		growthFactor *= obj.owner.PopulationGrowthFactor;
		growthFactor *= config::COLONIZING_GROWTH_PENALTY;
		growthFactor *= getPlanetLevel(LevelChainId, min(Level,obj.primaryResourceLevel)).popGrowth;
		if(obj.inCombat)
			growthFactor = 0;

		//Calculate projected final population
		double colonizes = colonization.length + 1.0;
		if(!isSendingColonizers)
			colonizes = 1.0;
		double finalPop = Population;
		finalPop -= colonizes;
		finalPop += colonizes * (1.0 - obj.owner.PopulationPerColonizer) * growthFactor;

		if(!needsPopulationForLevel)
			return finalPop >= 1.0;
		else
			return finalPop >= lv.requiredPop;
	}
	
	bool hasColonyTarget(Object& other) const {
		for(uint i = 0, cnt = colonization.length; i < cnt; ++i)
			if(colonization[i] is other)
				return true;
		return false;
	}
	
	uint get_colonyOrderCount() const {
		return colonization.length;
	}
	
	Object@ get_colonyTarget(uint index) const {
		if(index < colonization.length)
			return colonization[index];
		return null;
	}

	void setSystemCounter(uint index, uint amount) {
		if(icon !is null)
			icon.setCounter(index, amount);
	}

	double getResourceProduction(uint resource) {
		if(resource >= grid.resources.length)
			return 0.0;
		return grid.resources[resource];
	}

	double getResourcePressure(uint resource) {
		if(resource >= grid.pressures.length)
			return 0.0;
		return grid.pressures[resource];
	}

	void surfaceTick(Object& obj, double time) {
		//Set icon visibility
		if(icon !is null) {
			icon.visible = obj.isVisibleTo(playerEmpire);
			updateIconVision(obj);

			if(wasMoving != obj.isMoving) {
				if(wasMoving) {
					if(obj.region !is null)
						obj.region.addStrategicIcon(0, obj, icon);
				}
				else {
					if(obj.region !is null)
						obj.region.removeStrategicIcon(0, icon);
				}
				wasMoving = obj.isMoving;
			}
		}

		//Do level decay
		if(DecayTimer > 0)
			DecayTimer = max(0.0, DecayTimer - time);

		//Update icon
		uint mod = obj.resourceModID;
		if(mod != ResourceModID) {
			ResourceModID = mod;
			updateIcon(obj);
		}

		if(reqSurfaceData)
			requestSurface(obj);
	}

	void _readVis(Message& msg) {
		uint cnt = getEmpireCount();
		for(uint i = 0; i < cnt; ++i)
			msg >> iconMemory[i];
	}

	void _readPop(Message& msg) {
		MaxPopulation = msg.readSmall();
		Population = msg.read_float();
		Income = msg.readSignedSmall();
		msg >> Contestion;
		if(msg.readBit())
			growthRate = msg.read_float();
		else
			growthRate = 1.0;
		needsPopulationForLevel = msg.readBit();

		int maxLevel = getLevelChain(LevelChainId).levels.length-1;
		ResourceLevel = msg.readLimited(maxLevel);

		isSendingColonizers = msg.readBit();
	}

	void _readRes(Object& obj, Message& msg, bool initial = false) {
		uint prevLevel = Level;
		bool prevColonizing = ColonizingMask & playerEmpire.mask != 0;
		double prevDecay = DecayTimer;

		LevelChainId = msg.readLimited(getLevelChainCount());
		int maxLevel = getLevelChain(LevelChainId).levels.length-1;
		Level = msg.readLimited(maxLevel);

		if(msg.readBit()) {
			DecayLevel = msg.readLimited(Level-1);
			DecayTimer = msg.read_float();
		}
		else {
			DecayLevel = Level;
			DecayTimer = -1.0;
		}

		if(msg.readBit())
			maxPlanetLevel = msg.readSmall();
		else
			maxPlanetLevel = -1;
		
		if(msg.readBit())
			msg >> ColonizingMask;
		else
			ColonizingMask = 0;
		
		msg >> disableProtection;
		
		if(msg.readBit())
			colonyshipAccel = msg.read_float();
		else
			colonyshipAccel = 1.0;
		
		//Unlock achievement "Reach Level 4"
		if(!initial && Level == 4 && prevLevel < 4 && obj.owner is playerEmpire && !getCheatsEverOn())
			unlockAchievement("ACH_LEVEL4");

		if(icon !is null) {
			if(prevLevel != Level)
				icon.setLevel(Level);
			if((prevDecay < 0.0) != (DecayTimer < 0.0))
				updateIcon(obj);

			bool isColonizing = ColonizingMask & playerEmpire.mask != 0;
			if(prevColonizing != isColonizing)
				icon.setBeingColonized(isColonizing);
		}

		uint prevFlags = gfxFlags;
		if(msg.readBit())
			gfxFlags = msg.readSmall();
		else
			gfxFlags = 0;
		if(prevFlags != gfxFlags) {
			PlanetNode@ plNode = cast<PlanetNode>(obj.getNode());
			if(plNode !is null)
				plNode.flags = gfxFlags;
		}
	}

	void _readAff(Object& obj, Message& msg) {
		uint cnt = msg.readSmall();
		affinities.length = cnt;
		for(uint i = 0; i < cnt; ++i)
			affinities[i] = msg.readSmall();

		Quarantined = msg.readSmall();
	}

	void _readLoy(Object& obj, Message& msg) {
		BaseLoyalty = msg.readSignedSmall();
		LoyaltyBonus = msg.readSignedSmall();
		protectedFromMask = msg.readSmall();
		orbitsMask = msg.readSmall();
		double base = double(BaseLoyalty + obj.owner.GlobalLoyalty.value);
		for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i) {
			if(msg.readBit())
				LoyaltyEffect[i] = msg.readFixed(-base, 0, 12);
			else
				LoyaltyEffect[i] = 0;
		}
		if(icon !is null) {
			Empire@ captEmp = get_captureEmpire(obj);
			float captPct = get_capturePct(obj);
			icon.setCapture(captEmp, captPct);
		}
	}

	void _readColonization(Message& msg) {
		if(!msg.readBit())
			return;
		uint8 count = msg.read_uint8();
		colonization.length = count;
		for(uint8 i = 0; i < count; ++i)
			msg >> colonization[i];
	}

	void readSurfaceDelta(Object& obj, Message& msg) {
		if(msg.readBit())
			_readRes(obj, msg);
		if(msg.readBit())
			_readAff(obj, msg);
		if(msg.readBit())
			_readPop(msg);
		if(msg.readBit()) {
			if(grid.read(msg, true))
				++SurfaceModId;
		}
		if(msg.readBit())
			_readColonization(msg);
		if(msg.readBit())
			_readLoy(obj, msg);
	}

	Empire@ prevPlayer = playerEmpire;
	void updateIconVision(Object& obj) {
		uint resource = 0xfffe;
		if(obj.nativeResourceCount != 0) {
			const ResourceType@ type = getResource(obj.nativeResourceType[0]);
			resource = type.id;
		}

		//Update remembered icon states
		for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i) {
			Empire@ emp = getEmpire(i);

			if(obj.isVisibleTo(emp)) {
				int mem = iconMemory[i];
				if(mem != -1) {
					iconMemory[i] = -1;
					if(emp is playerEmpire)
						updateIcon(obj);
				}
			}
			else {
				int mem = iconMemory[i];
				if(mem == -1) {
					mem = 0;
					mem |= Level;
					mem |= obj.owner.id << 8;
					mem |= resource << 16;
					iconMemory[i] = mem;
					if(emp is playerEmpire)
						updateIcon(obj);
				}
			}
		}

		if(prevPlayer !is playerEmpire) {
			updateIcon(obj);
		}
	}

	void updateIcon(Object& obj) {
		//Update actual icon
		if(icon !is null) {
			if(obj.isVisibleTo(playerEmpire)) {
				//Use active
				icon.setLevel(Level);
				if(obj.nativeResourceCount != 0) {
					const ResourceType@ type = getResource(obj.nativeResourceType[0]);
					Object@ destination = obj.getNativeResourceDestination(playerEmpire, 0);

					icon.setResource(type.id);
					icon.setState(!obj.nativeResourceUsable[0],
							destination !is null,
							(type.isMaterial(Level) || destination !is null)
							&& (destination is null || !destination.owner.valid || destination.owner is obj.owner),
							DecayTimer > 0.0);
				}
				else {
					icon.setResource(uint(-1));
					icon.setState(false, false, true, false);
				}
			}
			else if(obj.isKnownTo(playerEmpire) && playerEmpire.valid) {
				int mem = iconMemory[playerEmpire.index];
				int level = mem & 0xff;
				int empId =(mem & 0xff00) >> 8;
				int res = (mem & 0xffff0000) >> 16;

				icon.setLevel(level);
				icon.setOwner(getEmpireByID(empId));

				if(res == 0xfffe) {
					icon.setResource(uint(-1));
					icon.setState(false, false, true, false);
				}
				else {
					icon.setResource(res);
					Object@ destination = obj.getNativeResourceDestination(playerEmpire, 0);
					icon.setState(false, destination !is null, true, false);
				}
			}
		}
	}

	void changeSurfaceRegion(Object& obj, Region@ prevRegion, Region@ newRegion) {
		if(icon !is null && !wasMoving) {
			if(prevRegion !is null)
				prevRegion.removeStrategicIcon(0, icon);
			if(newRegion !is null)
				newRegion.addStrategicIcon(0, obj, icon);
			else
				icon.clearStrategic();
		}
	}

	uint get_totalSurfaceTiles() const {
		return grid.tileBuildings.length;
	}

	uint get_usedSurfaceTiles() const {
		uint used = 0;
		for(uint i = 0, cnt = grid.buildings.length; i < cnt; ++i) {
			vec2u size = grid.buildings[i].type.size;
			used += size.x * size.y;
		}
		return used;
	}

	void destroySurface(Object& obj) {
		if(icon !is null) {
			Region@ region = obj.region;
			if(region !is null)
				region.removeStrategicIcon(0, icon);
			icon.markForDeletion();
		}
	}

	void readSurface(Object& obj, Message& msg) {
		_readPop(msg);
		_readRes(obj, msg, true);
		_readAff(obj, msg);
		_readLoy(obj, msg);
		_readVis(msg);
		_readColonization(msg);

		msg >> Quarantined;
		tileDevelopRate = msg.read_float();
		bldConstructRate = msg.read_float();
		undevelopedMaint = msg.read_float();

		originalSurfaceSize.x = msg.readSmall();
		originalSurfaceSize.y = msg.readSmall();
		biome0 = msg.readSmall();
		biome1 = msg.readSmall();
		biome2 = msg.readSmall();

		grid.read(msg);

		Planet@ pl = cast<Planet>(obj);
		if(pl !is null && icon is null) {
			@icon = PlanetIconNode();
			icon.establish(pl);
			updateIcon(obj);

			if(obj.region !is null)
				obj.region.addStrategicIcon(0, obj, icon);
		}
		else {
			updateIcon(obj);
		}
	}

	Image@ surfaceData;
	bool reqSurfaceData = false;
	uint surfaceDataMod = uint(-1);
	uint getSurfaceData(Object& obj, Image& img) {
		reqSurfaceData = true;
		if(surfaceData is null) {
			obj.requestSurface();
			return uint(-1);
		}

		img = surfaceData;
		return surfaceDataMod;
	}

	void requestSurface(Object& obj) {
		if(surfaceData is null)
			@surfaceData = Image(originalSurfaceSize, 4);
		if(surfaceDataMod != SurfaceModId) {
			renderSurfaceData(obj, grid, surfaceData, sizeLimit=originalSurfaceSize, citiesMode=true);
			surfaceDataMod = SurfaceModId;
		}
		reqSurfaceData = false;
	}

	uint get_surfaceModId() {
		return SurfaceModId;
	}

	vec2i get_surfaceGridSize() {
		return vec2i(grid.size);
	}

	vec2i get_originalGridSize() {
		return vec2i(originalSurfaceSize);
	}
}
