#include "include/resource_constants.as"

import saving;
import biomes;
import planet_levels;
import resources;
import systems;
import planets.SurfaceGrid;
import planet_loyalty;
import object_creation;
import planet_types;
import notifications;
import attributes;
from influence import DiplomacyEdictType;
from influence_global import giveRandomReward;
from components.ObjectManager import getDefenseDesign;
import bool getCheatsEverOn() from "cheats";
const string TAG_SUPPORT("Support");

bool INSTANT_COLONIZE = false;
void setInstantColonize(bool value) {
	INSTANT_COLONIZE = value;
}

tidy class SurfaceComponent : Component_SurfaceComponent, Savable {
	array<const Biome@> biomes;
	uint biome0, biome1, biome2;
	array<Object@> fleetsInOrbit;
	uint orbitsMask = 0;
	uint fakeSiegeOrbit = 0;
	uint forceSiegeMask = 0;
	vec2u originalSurfaceSize;

	double Population = 0.0;
	int MaxPopulation = 0;
	int PopulationPenalty = 0;
	int overpopulation = 0;
	double incomingPop = 0;
	int bombardDecay = 0;
	bool disableProtection = false;
	bool needsPopulationForLevel = true;
	uint protectedFromMask = 0;
	int maxPlanetLevel = -1;

	int prevIncome = 0;
	int popIncome = 0;
	int bonusIncome = 0;
	int prevPopulation = 0;
	int prevBaseLoyalty = 1;
	double prevInfluence = 0;
	double prevEnergy = 0;
	double prevResearch = 0;
	double prevDefense = 0;

	const Design@ defenseDesign;
	double defenseLabor = -1;

	PlanetIconNode@ icon;
	array<int> iconMemory(getEmpireCount(), -1);

	ColonizationOrder[] colonization;
	float colonyShipTimer = 0.f;
	bool isSendingColonizers = false;

	float pressureCapFactor = 1.f;
	int pressureCapMod = 0;

	uint ResourceModID = 0;
	array<uint> affinities;

	uint ColonizingMask = 0;
	uint Level = 0;
	uint DecayLevel = 0;
	uint ResourceLevel = 0;
	uint PopLevel = 0;
	uint LevelChainId = 0;
	double DecayTimer = -1.0;
	double ResourceCheck = 1.0;

	bool deltaRes = false;
	bool deltaAff = false;
	bool deltaPop = false;
	bool deltaCol = false;
	bool deltaLoy = false;
	bool wasMoving = false;

	int Quarantined = 0;
	int Contestion = 0;

	int BaseLoyalty = 10;
	int LoyaltyBonus = 0;
	float WaitingBaseLoyalty = 0;
	float StoredBaseLoyalty = 0;
	array<float> LoyaltyEffect(getEmpireCount(), 0);

	double growthRate = 1.0;
	double tileDevelopRate = 1.0;
	double bldConstructRate = 1.0;
	double undevelopedMaint = 1.0;
	double colonyshipAccel = 1.0;

	uint gfxFlags = 0;

	SurfaceGrid grid;
	uint SurfaceModId = 0;
	
	SurfaceComponent() {}
	
	void save(SaveFile& file) {
		file << Population;
		file << MaxPopulation;
		file << PopulationPenalty;
		file << overpopulation;
		file << ResourceModID;
		file << pressureCapFactor;
		file << pressureCapMod;
		file << bombardDecay;
		file << incomingPop;

		file << prevIncome;
		file << prevPopulation;
		file << prevInfluence;
		file << prevEnergy;
		file << prevResearch;
		file << prevDefense;
		file << popIncome;
		file << bonusIncome;

		file << growthRate;
		file << tileDevelopRate;
		file << bldConstructRate;
		file << undevelopedMaint;
		file << colonyshipAccel;

		file << Level;
		file << DecayLevel;
		file << PopLevel;
		file.writeIdentifier(SI_PlanetLevelChain, LevelChainId);
		file << ResourceLevel;
		file << prevBaseLoyalty;
		file << needsPopulationForLevel;
		file << DecayTimer;
		file << deltaPop;
		file << deltaRes;
		file << ColonizingMask;
		file << protectedFromMask;
		file << maxPlanetLevel;

		file << Quarantined;
		file << Contestion;

		file << BaseLoyalty;
		file << WaitingBaseLoyalty;
		file << StoredBaseLoyalty;
		file << LoyaltyBonus;
		file << disableProtection;
		uint cnt = getEmpireCount();
		for(uint i = 0; i < cnt; ++i) {
			file << LoyaltyEffect[i];
			file << iconMemory[i];
		}

		grid.save(file);
		
		file << colonyShipTimer;
		file << isSendingColonizers;
		file << uint8(colonization.length);
		for(uint8 i = 0; i < uint8(colonization.length); ++i)
			colonization[i].save(file);
		
		file << uint8(biomes.length);
		for(uint i = 0; i < biomes.length; ++i)
			file.writeIdentifier(SI_Biome, int(biomes[i].id));

		cnt = affinities.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i)
			file << affinities[i];

		file << gfxFlags;
		file << originalSurfaceSize;
	}
	
	void load(SaveFile& file) {
		file >> Population;
		file >> MaxPopulation;
		file >> PopulationPenalty;
		file >> overpopulation;
		file >> ResourceModID;
		file >> pressureCapFactor;
		file >> pressureCapMod;
		if(file >= SV_0038)
			file >> bombardDecay;
		if(file < SV_0088)
			file.readObject();
		if(file >= SV_0033)
			file >> incomingPop;

		file >> prevIncome;
		file >> prevPopulation;
		file >> prevInfluence;
		file >> prevEnergy;
		file >> prevResearch;
		file >> prevDefense;
		if(file < SV_0088)
			prevDefense = 0;
		file >> popIncome;
		if(file >= SV_0125)
			file >> bonusIncome;

		file >> growthRate;
		file >> tileDevelopRate;
		file >> bldConstructRate;
		file >> undevelopedMaint;
		file >> colonyshipAccel;

		ResourceCheck = 0;
		file >> Level;
		file >> DecayLevel;
		if(file >= SV_0058) {
			file >> PopLevel;
			if(file >= SV_0143) {
				LevelChainId = file.readIdentifier(SI_PlanetLevelChain);
				if(LevelChainId == uint(-1))
					LevelChainId = 0;
			}
			file >> ResourceLevel;
			file >> prevBaseLoyalty;
			file >> needsPopulationForLevel;
		}
		file >> DecayTimer;
		file >> deltaPop;
		file >> deltaRes;
		file >> ColonizingMask;
		if(file >= SV_0110)
			file >> protectedFromMask;
		if(file >= SV_0127)
			file >> maxPlanetLevel;

		file >> Quarantined;
		file >> Contestion;

		file >> BaseLoyalty;
		file >> WaitingBaseLoyalty;
		file >> StoredBaseLoyalty;
		file >> LoyaltyBonus;
		file >> disableProtection;
		uint cnt = getEmpireCount();
		for(uint i = 0; i < cnt; ++i) {
			file >> LoyaltyEffect[i];
			if(file < SV_0056) {
				float dummy = 0.f;
				file >> dummy;
				file >> dummy;
			}
			file >> iconMemory[i];
		}

		grid.load(file);
		
		file >> colonyShipTimer;
		file >> isSendingColonizers;
		uint8 colonyOrders = 0;
		file >> colonyOrders;
		colonization.length = colonyOrders;
		for(uint i = 0; i < colonization.length; ++i)
			colonization[i].load(file);
			
		uint8 biomeCount = 0;
		file >> biomeCount;
		biomes.length = biomeCount;
		for(uint i = 0; i < biomes.length; ++i) {
			uint8 id = uint8(file.readIdentifier(SI_Biome));
			@biomes[i] = getBiome(id);
		}

		if(biomes.length >= 1)
			biome0 = biomes[0].id;
		if(biomes.length >= 2)
			biome1 = biomes[1].id;
		if(biomes.length >= 3)
			biome2 = biomes[2].id;

		if(file < SV_0105) {
			bool b = false;
			uint u = 0;
			file >> b >> b >> b;
			file >> u;;
			file >> b;
			if(b) {
				file >> u;
				if(u == 0)
					file >> u;
			}
		}

		file >> cnt;
		affinities.length = cnt;
		for(uint i = 0; i < cnt; ++i)
			file >> affinities[i];

		if(file >= SV_0122)
			file >> gfxFlags;
		if(file >= SV_0150)
			file >> originalSurfaceSize;
	}

	void surfacePostLoad(Object& obj) {
		Planet@ pl = cast<Planet>(obj);
		if(pl !is null) {
			@icon = PlanetIconNode();
			icon.establish(pl);
			icon.setBeingColonized(ColonizingMask & playerEmpire.mask != 0);
			updateIcon(obj);

			if(obj.region !is null)
				obj.region.addStrategicIcon(0, obj, icon);
		}
	}

	void initSurface(Object& obj, int width, int height, uint one, uint two, uint three, uint resource) {
		initSurface(obj, width, height, getBiome(one), getBiome(two), getBiome(three), getResource(resource));
	}

	void initSurface(Object& obj, int width, int height, const Biome@ base, const Biome@ two, const Biome@ three, const ResourceType@ res) {
		//Set biomes
		biomes.length = 3;
		@biomes[0] = base;
		@biomes[1] = two;
		@biomes[2] = three;

		biome0 = base.id;
		biome1 = two.id;
		biome2 = three.id;

		//Generate grid
		grid.create(width, height, base);
		grid.generateContinent(two);
		grid.generateContinent(three);
		grid.rotateFor(base);

		//Create icon
		Planet@ pl = cast<Planet>(obj);
		if(pl !is null) {
			@icon = PlanetIconNode();
			icon.establish(pl);
			if(res !is null)
				icon.setResource(res.id);

			if(obj.region !is null)
				obj.region.addStrategicIcon(0, obj, icon);
		}

		setLevel(obj, 0, true);
		if(res !is null)
			obj.addResource(res.id);
		changeSurfaceOwner(obj, null);

		obj.canBuildShips = false;
		obj.canBuildAsteroids = false;
		obj.canBuildOrbitals = false;
		obj.canTerraform = false;

		++SurfaceModId;
		originalSurfaceSize = grid.size;
	}

	void addSurfaceArea(Object& obj, vec2i size, uint biome, uint voidBiome, bool separate, bool developed, bool vertical) {
		if(separate) {
			if(vertical)
				size.y += 1;
			else
				size.x += 1;
		}
		array<uint8> addBiomes(size.x * size.y);
		for(int x = 0; x < size.x; ++x) {
			for(int y = 0; y < size.y; ++y) {
				uint index = y * size.width + x;
				if(separate && (vertical ? (y == 0) : (x == 0)) && voidBiome != uint(-1))
					addBiomes[index] = voidBiome;
				else
					addBiomes[index] = biome;
			}
		}
		grid.addSurfaceArea(size, addBiomes, voidBiome, developed, vertical);

		++SurfaceModId;
	}

	void regenSurface(Object& obj, int width, int height, uint biomeCount) {
		biomes.length = biomeCount;
		for(uint i = 1; i < biomeCount; ++i)
			@biomes[i] = getDistributedBiome();
		if(biomes[0] is null)
			@biomes[0] = getDistributedBiome();

		if(biomes.length >= 1)
			biome0 = biomes[0].id;
		if(biomes.length >= 2)
			biome1 = biomes[1].id;
		if(biomes.length >= 3)
			biome2 = biomes[2].id;

		grid.create(width, height, biomes[0]);
		for(uint i = 1; i < biomeCount; ++i)
			grid.generateContinent(biomes[i]);

		grid.rotateFor(biomes[0]);

		++SurfaceModId;
		originalSurfaceSize = grid.size;
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

	void forceUsefulSurface(double pct, uint biomeId) {
		double useful = 1.0;
		double perTile = 1.0 / (double(grid.size.width) * double(grid.size.height));
		auto@ fillBiome = getBiome(biomeId);
		if(fillBiome is null)
			return;
		do {
			useful = 0;
			for(uint i = 0, cnt = grid.biomes.length; i < cnt; ++i) {
				auto@ other = getBiome(grid.biomes[i]);
				if(other !is null && other.buildCost <= 1.01f && other.buildTime <= 1.01f)
					useful += perTile;
			}
			if(useful < pct)
				grid.generateContinent(fillBiome, true);
		} while(useful < pct);

		++SurfaceModId;
	}

	bool hasBiome(uint id) const {
		for(uint i = 0, cnt = biomes.length; i < cnt; ++i) {
			if(biomes[i].id == id)
				return true;
		}
		return false;
	}

	void getPlanetSurface() {
		yield(grid);
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

	uint get_emptyDevelopedTiles() {
		return grid.emptyDeveloped;
	}

	void replaceAllBiomesWith(Object& obj, uint id) {
		for(uint i = 0, cnt = biomes.length; i < cnt; ++i)
			replaceBiome(obj, i, id);
	}

	void replaceFirstBiomeWith(Object& obj, uint id) {
		replaceBiome(obj, 0, id);
	}

	void replaceBiome(Object& obj, uint index, uint id) {
		auto@ repl = getBiome(id);
		if(repl is null)
			return;
		if(index >= biomes.length)
			return;
		if(biomes[index] is repl)
			return;

		//Replace the base biome with the new one
		uint8 prevId = uint8(biomes[index].id);
		uint8 newId = uint8(repl.id);
		if(prevId == newId)
			return;
		if(index == 0)
			@grid.baseBiome = repl;
		for(uint i = 0, cnt = biomes.length; i < cnt; ++i) {
			if(biomes[i].id == prevId)
				@biomes[i] = repl;
		}
		for(uint i = 0, cnt = grid.biomes.length; i < cnt; ++i) {
			if(grid.biomes[i] == prevId)
				grid.biomes[i] = newId;
		}
		grid.delta = true;

		//Figure out planet type
		Planet@ pl = cast<Planet>(obj);
		if(pl !is null) {
			const PlanetType@ planetType;
			if(biomes.length == 3)
				@planetType = getBestPlanetType(biomes[0], biomes[1], biomes[2]);
			else if(biomes.length == 1)
				@planetType = getBestPlanetType(biomes[0], null, null);
			if(planetType !is null) {
				pl.PlanetType = planetType.id;
				PlanetNode@ plNode = cast<PlanetNode>(pl.getNode());
				if(plNode !is null)
					plNode.planetType = planetType.id;
			}
		}

		++SurfaceModId;
		if(biomes.length >= 1)
			biome0 = biomes[0].id;
		if(biomes.length >= 2)
			biome1 = biomes[1].id;
		if(biomes.length >= 3)
			biome2 = biomes[2].id;
	}

	void mirrorSurfaceFrom(Object& obj, Object& other) {
		PlanetSurface surf;
		receive(other.getPlanetSurface(), surf);

		for(uint i = 0, cnt = min(grid.biomes.length, surf.biomes.length); i < cnt; ++i)
			grid.biomes[i] = surf.biomes[i];

		Planet@ pl = cast<Planet>(obj);
		Planet@ otherPl = cast<Planet>(other);
		if(pl !is null) {
			pl.PlanetType = otherPl.PlanetType;
			
			PlanetNode@ plNode = cast<PlanetNode>(pl.getNode());
			if(plNode !is null)
				plNode.planetType = pl.PlanetType;
		}

		++SurfaceModId;
		if(biomes.length >= 1)
			biome0 = biomes[0].id;
		if(biomes.length >= 2)
			biome1 = biomes[1].id;
		if(biomes.length >= 3)
			biome2 = biomes[2].id;
	}

	void removeFinalSurfaceRows(Object& obj, uint rows = 1) {
		grid.delta = true;
		for(uint x = 0; x < grid.size.width; ++x) {
			for(uint y = 0; y < rows; ++y) {
				uint index = (grid.size.height - rows + y) * grid.size.width + x;
				auto@ bld = grid.tileBuildings[index];
				if(bld !is null)
					grid.destroyBuilding(obj, vec2i(bld.position), force=true);

				if(grid.flags[index] & SuF_Usable != 0)
					grid.emptyDeveloped -= 1;
			}
		}

		grid.size = vec2u(grid.size.width, grid.size.height - rows);
		grid.biomes.length = grid.size.x * grid.size.y;
		grid.flags.length = grid.size.x * grid.size.y;
		grid.tileBuildings.length = grid.size.x * grid.size.y;

		++SurfaceModId;
	}

	void stealFinalSurfaceRowsFrom(Object& obj, Object& other, uint rows = 1, uint voidBiome = uint(-1)) {
		PlanetSurface surf;
		receive(other.getPlanetSurface(), surf);

		//Detect the non-void area in the center
		uint leftOff = 0;
		uint rightOff = 0;
		for(uint x = 0; x < surf.size.width; ++x) {
			bool fullVoid = true;
			for(uint y = 0; y < rows; ++y) {
				uint copyIndex = (surf.size.height - rows + y) * surf.size.width + x;
				if(surf.biomes[copyIndex] != voidBiome) {
					fullVoid = false;
					break;
				}
			}
			if(fullVoid)
				leftOff += 1;
			else
				break;
		}
		for(uint x = 0; x < surf.size.width; ++x) {
			bool fullVoid = true;
			for(uint y = 0; y < rows; ++y) {
				uint copyIndex = (surf.size.height - rows + y) * surf.size.width + (surf.size.width - x - 1);
				if(surf.biomes[copyIndex] != voidBiome) {
					fullVoid = false;
					break;
				}
			}
			if(fullVoid)
				rightOff += 1;
			else
				break;
		}
		int addWidth = surf.size.width - leftOff - rightOff;
		if(addWidth <= 0)
			return;

		//Add the biomes to our surface
		array<uint8> addBiomes(rows * addWidth);
		array<bool> devState(rows * addWidth);
		for(int x = 0; x < addWidth; ++x) {
			for(uint y = 0; y < rows; ++y) {
				uint addIndex = y * addWidth + x;
				uint copyIndex = (surf.size.height - rows + y) * surf.size.width + (x + leftOff);

				addBiomes[addIndex] = surf.biomes[copyIndex];
				devState[addIndex] = surf.flags[copyIndex] & SuF_Usable != 0;
			}
		}
		grid.addSurfaceArea(vec2i(addWidth, rows), addBiomes, voidBiome, false, true, @devState);

		//Spwan copies of all the buildings
		vec2i bldOffset((grid.size.width - addWidth) / 2 - leftOff, grid.size.height - surf.size.height);
		for(int x = 0; x < addWidth; ++x) {
			for(uint y = 0; y < rows; ++y) {
				uint copyIndex = (surf.size.height - rows + y) * surf.size.width + (x + leftOff);
				auto@ bld = surf.tileBuildings[copyIndex];
				if(bld !is null && (bld.type.laborCost <= 0 || bld.completion >= 1.f)) {
					vec2i newPos = vec2i(bld.position) + bldOffset;
					uint newIndex = newPos.y * grid.size.width + newPos.x;
					if(grid.tileBuildings[newIndex] is null) {
						float completion = bld.completion;
						if(completion < 1.f && bld.type.cls != BC_Building)
							completion = 1.f;
						grid.build(obj, bld.type, newPos, true, false, completion);
					}
				}
			}
		}

		//Tell the other to remove their rows
		other.removeFinalSurfaceRows(rows);

		++SurfaceModId;
	}

	void changeSurfaceTerritory(Territory@ prev, Territory@ terr) {
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
			Empire@ ownerEmp = getEmpireByID((iconMemory[emp.index] & 0xff00) >> 8);
			if(ownerEmp is null)
				return defaultEmpire;
			else
				return ownerEmp;
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
	
	Empire@ visibleOwnerToEmp(const Object& obj, Empire@ emp) const {
		if(emp is null)
			return defaultEmpire;
		if(obj.isVisibleTo(emp))
			return obj.owner;
		if(obj.isKnownTo(emp) && emp.valid) {
			Empire@ ownerEmp = getEmpireByID((iconMemory[emp.index] & 0xff00) >> 8);
			if(ownerEmp is null)
				return defaultEmpire;
			else
				return ownerEmp;
		}
		return defaultEmpire;
	}

	void buildBuilding(Object& obj, uint tid, vec2i pos) {
		const BuildingType@ type = getBuildingType(tid);
		if(type is null)
			return;
		if(type.civilian || !type.canBuildOn(obj))
			return;
		if(pos.x < 0 || pos.y < 0)
			return;
		if(pos.x >= int(grid.size.x) || pos.y >= int(grid.size.y))
			return;

		grid.build(obj, type, pos);
		++SurfaceModId;
	}
	
	int getBuildingAt(uint x, uint y) {
		auto@ bldg = grid.getBuilding(x, y);
		if(bldg !is null)
			return bldg.type.id;
		else
			return -1;
	}

	void setBuildingCompletion(Object& obj, uint x, uint y, float progress) {
		grid.setBuildingCompletion(obj, vec2i(x,y), progress);
	}
	
	float getBuildingProgressAt(uint x, uint y) {
		auto@ bldg = grid.getBuilding(x, y);
		if(bldg !is null)
			return bldg.completion;
		else
			return 0.f;
	}

	void destroyBuilding(Object& obj, vec2i pos) {
		grid.destroyBuilding(obj, pos);
		++SurfaceModId;
	}

	void forceDestroyBuilding(Object& obj, vec2i pos, bool undevelop = false) {
		grid.destroyBuilding(obj, pos, undevelop=undevelop, force=true);
		++SurfaceModId;
	}

	void spawnBuilding(Object& obj, uint tid, vec2i pos, bool develop = false) {
		const BuildingType@ type = getBuildingType(tid);
		if(type is null)
			return;
		if(type.civilian)
			return;
		if(pos.x < 0 || pos.y < 0)
			return;
		if(pos.x >= int(grid.size.x) || pos.y >= int(grid.size.y))
			return;

		grid.build(obj, type, pos, true, develop=develop);
		++SurfaceModId;
	}

	void modCityCount(Object& obj, int mod) {
		grid.citiesBuilt += mod;
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

	bool isPressureSaturated(uint resource) {
		if(resource >= grid.pressures.length)
			return true;
		return grid.saturates[resource] >= grid.pressures[resource] - 0.01;
	}

	double getCivilianProduction(uint resource) {
		if(resource >= grid.civResources.length)
			return 0.0;
		return grid.civResources[resource];
	}

	void modResource(uint resource, double amount) {
		if(resource >= grid.resources.length)
			return;
		grid.resources[resource] += amount;
	}

	void modCivResourceMod(uint resource, double amount) {
		if(resource >= grid.civResourceMods.length)
			return;
		float prev = grid.civResourceMods[resource];
		grid.civResourceMods[resource] += amount;

		double oldRes = prev * double(grid.civResources[resource]);
		double newRes = grid.civResourceMods[resource] * double(grid.civResources[resource]);
		if(oldRes != newRes)
			grid.resources[resource] += (newRes - oldRes);
	}

	float getCivResourceMod(uint resource) {
		if(resource >= grid.civResourceMods.length)
			return 0.f;
		return grid.civResourceMods[resource];
	}

	void modOverpopulation(int steps) {
		overpopulation += steps;
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

	void developTiles(Object& obj, uint amount) {
		grid.developTiles(obj, amount);
	}
	
	void destroyRandomTile(Object& obj, bool civilOnly) {
		grid.destroyRandomTile(obj, civilOnly);
	}
	
	void modBombardment(int amount) {
		bombardDecay += amount;
	}

	void modPressureCapFactor(Object& obj, float amt) {
		pressureCapFactor += amt;
		calculatePopVars(obj);
	}

	void modPressureCapMod(Object& obj, int amt) {
		pressureCapMod += amt;
		calculatePopVars(obj);
	}

	void modBuildingMaintenanceRefund(int amt) {
		grid.bldMaintenanceRefund += amt;
	}

	uint get_pressureCap() const {
		return grid.pressureCap;
	}

	float get_totalPressure() const {
		return grid.totalPressure;
	}

	void modGrowthRate(double amt) {
		growthRate += amt;
		deltaPop = true;
	}

	void modTileDevelopRate(double amt) {
		tileDevelopRate += amt;
	}

	void modBuildingConstructRate(double amt) {
		bldConstructRate += amt;
	}

	void modUndevelopedMaintenance(double amt) {
		undevelopedMaint *= amt;
	}

	int get_income() const {
		return prevIncome - max(grid.Maintenance, 0);
	}

	int get_buildingMaintenance() const {
		return grid.Maintenance;
	}

	void set_maxLevel(Object& obj, int lv) {
		if(maxPlanetLevel != lv) {
			maxPlanetLevel = lv;
			deltaRes = true;
			if(Level > uint(maxPlanetLevel))
				updateDecayLevel(obj, 0.0, true);
			else if(uint(maxPlanetLevel) > Level)
				ResourceModID = 0;
		}
	}

	int get_maxLevel() {
		return maxPlanetLevel;
	}

	double get_decayTime() const {
		return DecayTimer;
	}

	void setProtectionDisabled(bool val) {
		disableProtection = val;
		deltaRes = true;
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

	bool get_isUnderSiege(const Object& obj) const {
		bool haveSiege = false;
		for(uint i = 0, cnt = LoyaltyEffect.length; i < cnt; ++i) {
			if(LoyaltyEffect[i] < -0.01) {
				haveSiege = true;
				break;
			}
		}
		if((orbitsMask | fakeSiegeOrbit | forceSiegeMask) & obj.owner.hostileMask != 0)
			return haveSiege;
		return false;
	}

	bool get_isOverPressure() const {
		return grid.totalPressure > int(grid.pressureCap);
	}

	bool get_isGettingRelief(const Object& obj) const {
		Empire@ owner = obj.owner;
		if(owner.ForcedPeaceMask & fakeSiegeOrbit != 0)
			return true;
		for(uint i = 0, cnt = fleetsInOrbit.length; i < cnt; ++i) {
			Empire@ other = fleetsInOrbit[i].owner;
			if(owner is other || owner.ForcedPeaceMask & other.mask != 0)
				return true;
		}
		return false;
	}

	bool get_enemiesInOrbit(const Object& obj) const {
		Empire@ owner = obj.owner;
		for(uint i = 0, cnt = fleetsInOrbit.length; i < cnt; ++i) {
			Empire@ other = fleetsInOrbit[i].owner;
			if(owner.isHostile(other))
				return true;
		}
		return false;
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

	void modLoyaltyFacing(Empire@ emp, double mod) {
		deltaLoy = true;
		LoyaltyEffect[emp.index] += mod;
	}
	
	void restoreLoyalty(double amount) {
		for(uint i = 0, cnt = LoyaltyEffect.length; i < cnt; ++i)
			LoyaltyEffect[i] = min(LoyaltyEffect[i] + float(amount), 0.f);
	}

	void modBaseLoyalty(Object& obj, int mod) {
		deltaLoy = true;
		if(mod > 0) {
			WaitingBaseLoyalty += mod;
		}
		else {
			int take = floor(min(-double(mod), WaitingBaseLoyalty));
			if(take != 0) {
				WaitingBaseLoyalty -= take;
				mod += take;
			}
			BaseLoyalty += mod;

			double base = max(double(BaseLoyalty + obj.owner.GlobalLoyalty.value), 1.0);
			for(uint i = 0, cnt = LoyaltyEffect.length; i < cnt; ++i)
				LoyaltyEffect[i] = clamp(LoyaltyEffect[i], -base, 0.0);
		}
	}

	void applyBaseLoyalty() {
		double apply = floor(WaitingBaseLoyalty + StoredBaseLoyalty);
		if(apply > 0) {
			BaseLoyalty += int(apply);

			double take = max(StoredBaseLoyalty, apply);
			StoredBaseLoyalty -= take;
			WaitingBaseLoyalty -= (apply - take);
		}
	}

	void setLoyaltyBonus(Object& obj, int bonus) {
		int prev = LoyaltyBonus;
		if(prev != bonus) {
			LoyaltyBonus = bonus;
			modBaseLoyalty(obj, LoyaltyBonus - prev);
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

	vec2i get_surfaceGridSize() {
		return vec2i(grid.size);
	}

	vec2i get_originalGridSize() {
		return vec2i(originalSurfaceSize);
	}

	void destroySurface(Object& obj) {
		if(Level >= 3)
			obj.owner.modAttribute(EA_Level3Planets, AC_Add, -1);
		if(icon !is null) {
			Region@ region = obj.region;
			if(region !is null)
				region.removeStrategicIcon(0, icon);
			icon.markForDeletion();
		}
		grid.gridDestroy(obj);
	}

	void fakeSiege(uint mask) {
		fakeSiegeOrbit |= mask;
	}

	void clearFakeSiege(uint mask) {
		fakeSiegeOrbit &= ~mask;
	}

	void forceSiege(uint mask) {
		forceSiegeMask |= mask;
	}

	void clearForceSiege(uint mask) {
		forceSiegeMask &= ~mask;
	}

	uint siegeMask = 0;
	void updateLoyalty(Object& obj, double time) {
		Region@ reg = obj.region;
		if(obj.owner is null || !obj.owner.valid || reg is null) {
			for(uint i = 0, cnt = LoyaltyEffect.length; i < cnt; ++i)
				LoyaltyEffect[i] = 0;
			return;
		}

		Empire@ owner = obj.owner;
		bool contested = (reg !is null && reg.ContestedMask & owner.mask != 0) || obj.inCombat;
		bool isSiege = false;
		bool isRelief = false, externalRelief = false;
		bool protect = isProtected(obj);

		double baseLoyalty = max(double(BaseLoyalty + obj.owner.GlobalLoyalty.value), 1.0);
		double loyTimer = config::SIEGE_LOYALTY_TIME * ceil(baseLoyalty / 10.0);
		double loyMod = time * baseLoyalty / loyTimer / obj.owner.CaptureTimeDifficulty;
		double orbRadiusSQ = sqr(cast<Planet>(obj).OrbitSize);
		siegeMask = 0;

		uint prevOrbits = orbitsMask;
		uint newOrbits = 0;

		//Find out if we're getting any relief
		if(obj.supportCount > 0)
			isRelief = true;
		for(uint i = 0, cnt = fleetsInOrbit.length; i < cnt; ++i) {
			Empire@ otherOwner = fleetsInOrbit[i].owner;
			newOrbits |= otherOwner.mask;
			if(otherOwner is owner) {
				isRelief = true;
				externalRelief = true;
			}
			else if(owner.ForcedPeaceMask & otherOwner.mask != 0) {
				isRelief = true;
				externalRelief = true;
			}
		}
		if(fakeSiegeOrbit != 0) {
			for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i) {
				Empire@ otherOwner = getEmpire(i);
				if(fakeSiegeOrbit & otherOwner.mask == 0)
					continue;

				newOrbits |= otherOwner.mask;
				if(otherOwner is owner) {
					isRelief = true;
					externalRelief = true;
				}
				else if(owner.ForcedPeaceMask & otherOwner.mask != 0) {
					isRelief = true;
					externalRelief = true;
				}
			}
		}

		if(prevOrbits != newOrbits) {
			orbitsMask = newOrbits;
			deltaLoy = true;
		}

		//Find out our total siege status
		if(fakeSiegeOrbit != 0 || forceSiegeMask != 0) {
			for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i) {
				Empire@ otherOwner = getEmpire(i);
				if(forceSiegeMask & otherOwner.mask != 0 || (fakeSiegeOrbit & otherOwner.mask != 0
							&& !protect && !isRelief && !isProtected(obj, otherOwner) && owner.ForcedPeaceMask & otherOwner.mask == 0)) {
					if(siegeMask & otherOwner.mask != 0)
						continue;

					siegeMask |= otherOwner.mask;

					isSiege = true;
					obj.engaged = true;
					contested = true;
					if(forceSiegeMask & otherOwner.mask != 0)
						externalRelief = false;

					double localMod = loyMod / otherOwner.CaptureTimeFactor;
					LoyaltyEffect[otherOwner.index] = clamp(LoyaltyEffect[otherOwner.index] - localMod, -baseLoyalty, 0.0);
					deltaLoy = true;
				}
			}
		}

		uint i = randomi(0, fleetsInOrbit.length-1);
		for(uint n = 0, cnt = fleetsInOrbit.length; n < cnt; ++n) {
			i = (i+1) % cnt;
			Object@ fleet = fleetsInOrbit[i];
			Ship@ ship = cast<Ship>(fleet);
			if(fleet is null || !fleet.valid || fleet.position.distanceToSQ(obj.position) > orbRadiusSQ) {
				fleetsInOrbit.removeAt(i);
				--i; --cnt;
				continue;
			}
			if(ship !is null && ship.Supply <= 0.001)
				continue;

			Empire@ otherOwner = fleetsInOrbit[i].owner;
			if(owner.isHostile(otherOwner) && !isProtected(obj, otherOwner) && !isRelief) {
				if(siegeMask & otherOwner.mask != 0)
					continue;
				if(ship !is null && ship.isStation)
					continue;

				siegeMask |= otherOwner.mask;

				isSiege = true;
				obj.engaged = true;
				contested = true;

				double localMod = loyMod / otherOwner.CaptureTimeFactor;
				if(ship !is null)
					ship.consumeSupply(localMod * config::SIEGE_LOYALTY_SUPPLY_COST * otherOwner.CaptureSupplyFactor * owner.CaptureSupplyDifficulty);
				LoyaltyEffect[otherOwner.index] = clamp(LoyaltyEffect[otherOwner.index] - localMod, -baseLoyalty, 0.0);
				deltaLoy = true;
			}
		}

		//Update base loyalty over time when not contested
		if(!contested) {
			if(WaitingBaseLoyalty > 0) {
				double take = min(WaitingBaseLoyalty, loyMod);
				if(take != 0) {
					StoredBaseLoyalty += take;
					WaitingBaseLoyalty -= take;
				}
			}
			while(StoredBaseLoyalty > 1.0) {
				StoredBaseLoyalty -= 1.0;
				BaseLoyalty += 1;
			}
		}

		//Regain loyalty over time when not contested
		if(!contested || externalRelief) {
			for(uint i = 0, cnt = LoyaltyEffect.length; i < cnt; ++i) {
				double prevEff = LoyaltyEffect[i];
				LoyaltyEffect[i] = clamp(prevEff + loyMod, -baseLoyalty, 0.0);
				if(LoyaltyEffect[i] != prevEff)
					deltaLoy = true;
			}
		}

		if(deltaLoy && icon !is null) {
			Empire@ captEmp = get_captureEmpire(obj);
			float captPct = get_capturePct(obj);
			icon.setCapture(captEmp, captPct);
		}

		//Planets under siege cannot gain supports
		obj.canGainSupports = !isSiege;
	}

	void enterIntoOrbit(Object@ ship) {
		if(fleetsInOrbit.find(ship) == -1)
			fleetsInOrbit.insertLast(ship);
	}

	void leaveFromOrbit(Object@ ship) {
		fleetsInOrbit.remove(ship);
	}

	void absoluteSiege(Object& obj, Empire@ fromEmpire, double loyAmount) {
		LoyaltyEffect[fromEmpire.index] -= loyAmount;
		obj.engaged = true;
		deltaLoy = true;
	}

	void setQuarantined(Object& obj, bool value) {
		if(value) {
			if(Quarantined <= 0) {
				obj.setExportEnabled(false);
				obj.setImportEnabled(false);
			}
			++Quarantined;
		}
		else {
			--Quarantined;
			if(Quarantined <= 0) {
				obj.setExportEnabled(true);
				obj.setImportEnabled(true);
			}
		}
		deltaAff = true;
	}

	void setContestion(Object& obj, bool value) {
		if(value)
			++Contestion;
		else
			--Contestion;
		deltaPop = true;
	}

	bool get_hasContestion() {
		return Contestion > 0;
	}

	bool get_isContested(const Object& obj) const {
		int cont = Contestion;
		if(cont > 0)
			return true;

		for(uint i = 0, cnt = LoyaltyEffect.length; i < cnt; ++i) {
			Empire@ emp = getEmpire(i);
			if(!emp.major || emp is obj.owner)
				continue;
			if(LoyaltyEffect[i] < -0.01)
				return true;
		}
		return false;
	}
	
	uint get_level() {
		return Level;
	}

	uint get_levelChain() {
		return LevelChainId;
	}

	uint get_resourceLevel() {
		return ResourceLevel;
	}

	bool get_quarantined() {
		return Quarantined > 0;
	}

	void setResourceLevel(Object& obj, uint lvl) {
		if(maxPlanetLevel >= 0)
			lvl = min(lvl, maxPlanetLevel);
		if(lvl != ResourceLevel)
			deltaRes = true;
		ResourceLevel = lvl;
	}

	void setNeedsPopulationForLevel(bool value) {
		needsPopulationForLevel = value;
		deltaPop = true;
	}

	void updateDecayLevel(Object& obj, double time, bool wasManual = false) {
		//Find the correct current target level
		uint TargetLevel = min(ResourceLevel, uint(maxPlanetLevel));
		bool isInstant = false;
		while(TargetLevel > 0 && needsPopulationForLevel) {
			if(Population < getPlanetLevelRequiredPop(LevelChainId, TargetLevel) - 0.001) {
				TargetLevel -= 1;
			}
			else {
				break;
			}
		}
		if(TargetLevel < ResourceLevel && Level > TargetLevel) {
			isInstant = true;
			if(isSendingColonizers)
				wasManual = true;
		}

		//Update population level
		uint newPopLevel = max(Level, ResourceLevel);
		if(newPopLevel != PopLevel) {
			const PlanetLevel@ prevLevel = getPlanetLevel(LevelChainId, PopLevel);
			const PlanetLevel@ newLevel = getPlanetLevel(LevelChainId, newPopLevel);
			modMaxPopulation(obj, int(newLevel.population) - int(prevLevel.population));
			PopLevel = newPopLevel;
		}

		//Update decay if we dropped levels
		if(TargetLevel >= Level || (TargetLevel < Level && (wasManual || isInstant))) {
			bool wasDecay = DecayTimer >= 0.0;
			DecayLevel = TargetLevel;
			DecayTimer = -1.0;
			if(wasDecay)
				updateIcon(obj);
			setLevel(obj, TargetLevel, false, wasManual);
		}
		else if(TargetLevel < Level) {
			DecayLevel = TargetLevel;
			double timer = config::LEVEL_DECAY_TIMER / obj.owner.PlanetDecaySpeed;
			if(DecayTimer < 0 || DecayTimer > timer)
				DecayTimer = timer;
			updateIcon(obj);
			deltaRes = true;
		}

		//Update decay timer
		if(time > 0 && DecayLevel < Level) {
			DecayTimer -= time;
			if(DecayTimer < 0) {
				if(DecayLevel < Level)
					DecayTimer = config::LEVEL_DECAY_TIMER * (DecayLevel + 1) / obj.owner.PlanetDecaySpeed;
				else
					DecayTimer = -1.0;

				setLevel(obj, Level - 1, false);
			}
		}
	}

	void setLevel(Object& obj, uint lvl, bool first = false, bool wasManual = false) {
		if(!first && lvl == Level)
			return;

		const PlanetLevel@ prevLevel = getPlanetLevel(LevelChainId, Level);
		const PlanetLevel@ newLevel = getPlanetLevel(LevelChainId, lvl);

		uint pLevel = Level;
		Level = lvl;
		deltaRes = true;

		applyLevel(obj, prevLevel, newLevel, first);
		
		//Unlock achievement "Reach Level 4"
		if(pLevel < 4 && Level == 4 && obj.owner is playerEmpire && !getCheatsEverOn())
			unlockAchievement("ACH_LEVEL4");

		obj.setResourceLevel(lvl, wasManual);

		if(pLevel < 3 && Level >= 3)
			obj.owner.modAttribute(EA_Level3Planets, AC_Add, 1);
		else if(pLevel >= 3 && Level < 3)
			obj.owner.modAttribute(EA_Level3Planets, AC_Add, -1);
	}

	void applyLevel(Object& obj, const PlanetLevel@ prevLevel, const PlanetLevel@ newLevel, bool first = false) {
		Region@ region = obj.region;
		double NeighbourLoyalty;

		if(first) {
			MaxPopulation = newLevel.population;
			BaseLoyalty = newLevel.baseLoyalty;
			NeighbourLoyalty = newLevel.neighbourLoyalty;
			prevBaseLoyalty = BaseLoyalty;
			DecayLevel = Level;
			DecayTimer = -1.0;
			obj.modSupplyCapacity(+newLevel.baseSupport);
		}
		else {
			NeighbourLoyalty = newLevel.neighbourLoyalty - prevLevel.neighbourLoyalty;
			obj.modSupplyCapacity(newLevel.baseSupport - prevLevel.baseSupport);
		}

		if(obj.owner !is null && obj.owner.valid) {
			obj.owner.points += (newLevel.points - prevLevel.points);

			if(region !is null)
				region.modNeighbourLoyalty(obj.owner, NeighbourLoyalty);
		}

		if(icon !is null)
			updateIcon(obj);
	}

	void setLevelChain(Object& obj, uint chainId, bool wasManual = true) {
		if(chainId == LevelChainId)
			return;
		auto@ chain = getLevelChain(chainId);
		if(chain is null)
			return;

		//Reset back to that chain's level 0 to apply everything
		const PlanetLevel@ prevLevel = getPlanetLevel(LevelChainId, Level);
		const PlanetLevel@ newLevel = getPlanetLevel(chainId, 0);

		applyLevel(obj, prevLevel, newLevel);

		Level = 0;
		deltaRes = true;

		LevelChainId = chainId;
		obj.setResourceLevel(0, wasManual);
		ResourceModID = uint(-1);
	}

	void changeSurfaceOwner(Object& obj, Empire@ prevOwner) {
		const PlanetLevel@ lvl = getPlanetLevel(LevelChainId, obj.level);
		Region@ region = obj.region;

		//Reset all loyalty values
		for(uint i = 0, cnt = LoyaltyEffect.length; i < cnt; ++i)
			LoyaltyEffect[i] = 0;
		applyBaseLoyalty();
		deltaLoy = true;
		grid.gridChangeOwner(obj, prevOwner, obj.owner);

		if(icon !is null) {
			Empire@ captEmp = get_captureEmpire(obj);
			float captPct = get_capturePct(obj);
			icon.setCapture(captEmp, captPct);
		}

		//Remove stuff from old empire
		if(prevOwner !is null && prevOwner.valid) {
			if(prevIncome != 0) {
				if(prevIncome > 0)
					prevOwner.modTotalBudget(-prevIncome, MoT_Planet_Income);
				else
					prevOwner.modTotalBudget(-prevIncome, MoT_Planet_Upkeep);
			}
			if(prevResearch != 0)
				prevOwner.modResearchRate(-double(prevResearch) * TILE_RESEARCH_RATE);
			if(prevInfluence != 0)
				prevOwner.modInfluenceIncome(-prevInfluence);
			if(prevEnergy != 0)
				prevOwner.modEnergyIncome(-double(prevEnergy) * TILE_ENERGY_RATE);
			if(region !is null)
				region.modNeighbourLoyalty(prevOwner, -lvl.neighbourLoyalty);
			if(prevPopulation != 0)
				prevOwner.modTotalPopulation(-prevPopulation);
			if(prevDefense < 0)
				prevOwner.modDefenseRate(prevDefense);
			else if(prevDefense > 0)
				prevOwner.modLocalDefense(-prevDefense);
			if(Level >= 3)
				prevOwner.modAttribute(EA_Level3Planets, AC_Add, -1);
			prevOwner.points -= lvl.points;
		}
		
		//Move stuff to new empire
		if(obj.owner !is null && obj.owner.valid) {
			if(prevIncome != 0) {
				if(prevIncome > 0)
					obj.owner.modTotalBudget(prevIncome, MoT_Planet_Income);
				else
					obj.owner.modTotalBudget(prevIncome, MoT_Planet_Upkeep);
			}
			if(prevResearch != 0)
				obj.owner.modResearchRate(double(prevResearch) * TILE_RESEARCH_RATE);
			if(prevInfluence != 0)
				obj.owner.modInfluenceIncome(prevInfluence);
			if(prevEnergy != 0)
				obj.owner.modEnergyIncome(double(prevEnergy) * TILE_ENERGY_RATE);
			if(region !is null)
				region.modNeighbourLoyalty(obj.owner, +lvl.neighbourLoyalty);
			if(grid.usableTiles == 0)
				grid.colonize(obj);
			if(prevPopulation != 0)
				obj.owner.modTotalPopulation(+prevPopulation);
			if(prevDefense < 0)
				obj.owner.modDefenseRate(-prevDefense);
			else if(prevDefense > 0)
				obj.owner.modLocalDefense(prevDefense);
			if(Level >= 3)
				obj.owner.modAttribute(EA_Level3Planets, AC_Add, +1);
			obj.owner.points += lvl.points;
		}

		//Remove colonization orders
		for(uint i = 0, cnt = colonization.length; i < cnt; ++i)
			prevOwner.unregisterColonization(obj, colonization[i].target, false);
		colonization.length = 0;
	}

	void changeSurfaceRegion(Object& obj, Region@ prevRegion, Region@ newRegion) {
		if(icon !is null)
			icon.hintParentObject(obj.region, false);
		const PlanetLevel@ lvl = getPlanetLevel(LevelChainId, obj.level);
		if(obj.owner !is null && obj.owner.valid) {
			if(prevRegion !is null)
				prevRegion.modNeighbourLoyalty(obj.owner, -lvl.neighbourLoyalty);
			if(newRegion !is null)
				newRegion.modNeighbourLoyalty(obj.owner, +lvl.neighbourLoyalty);
		}
		if(icon !is null) {
			if(!wasMoving) {
				if(prevRegion !is null)
					prevRegion.removeStrategicIcon(0, icon);
				if(newRegion !is null)
					newRegion.addStrategicIcon(0, obj, icon);
				else
					icon.clearStrategic();
			}
		}
	}

	double get_population() const {
		return Population;
	}
	
	uint get_maxPopulation() const {
		return MaxPopulation;
	}

	void colonyShipArrival(Object& obj, Empire@ owner, double population) {
		if(Quarantined != 0)
			return;
		if(obj.owner !is owner && (obj.owner is null || !obj.owner.valid)) {
			@obj.owner = owner;
			owner.recordEvent(stat::Planets, 1, obj.name);
		}
		addPopulation(obj, population);
		modIncomingPop(-population);
	}

	void addPopulation(Object& obj, double amt, bool allowOver = true) {
		if(Population < double(MaxPopulation) || allowOver) {
			Population = Population + amt;
			if(!allowOver)
				Population = min(Population, double(MaxPopulation));
			calculatePopVars(obj);
			deltaPop = true;
		}
	}
	
	void removePopulation(Object& obj, double amt, double minimum) {
		if(Population > minimum) {
			Population = max(Population - amt, minimum);
			calculatePopVars(obj);
			if(Population <= 0.00001)
				@obj.owner = defaultEmpire;
			deltaPop = true;
		}
	}

	void modMaxPopulation(Object& obj, int amt) {
		deltaPop = true;
		if(amt > 0) {
			if(PopulationPenalty >= amt) {
				PopulationPenalty -= amt;
			}
			else if(PopulationPenalty > 0) {
				amt -= PopulationPenalty;
				PopulationPenalty = 0;
				MaxPopulation += amt;
			}
			else {
				MaxPopulation += amt;
			}
		}
		else if(amt < 0) {
			int prev = MaxPopulation;
			MaxPopulation = max(1, MaxPopulation - (-amt));
			PopulationPenalty += (-amt) - (prev - MaxPopulation);
		}
	}

	//Colonize different planets
	void colonize(Object& obj, Object& other, double toPopulation) {
		if(toPopulation < 1.0)
			return;
		if(!other.isPlanet || other.quarantined)
			return;
		for(uint i = 0, cnt = colonization.length; i < cnt; ++i) {
			if(colonization[i].target is other) {
				if(colonization[i].targetPopulation < toPopulation)
					colonization[i].targetPopulation = toPopulation;
				return;
			}
		}

		ColonizationOrder order;
		@order.target = other;
		order.targetPopulation = toPopulation;
		colonization.insertLast(order);
		obj.owner.registerColonization(obj, other);
		deltaCol = true;
		isSendingColonizers = true;
	}
	
	void processColonization(Object& obj) {
		bool isSending = false;
		const double popPerShip = obj.owner.PopulationPerColonizer;
		if(Population < 1.0 + popPerShip || MaxPopulation <= 1.0 || obj.owner.ForbidColonization != 0) {
			//If we have insufficient population due to a low maximum, cancel all colony orders
			if(MaxPopulation <= 1.0 || obj.owner.ForbidColonization != 0) {
				uint cnt = colonization.length;
				if(cnt > 0) {
					for(uint i = 0; i < cnt; ++i)
						obj.owner.unregisterColonization(obj, colonization[i].target, cancel=false);
					colonization.length = 0;
				}
				isSendingColonizers = false;
			}
			return;
		}
		
		//Process a random colonization order per attempt
		for(uint i = 0, cnt = colonization.length; i < cnt; ++i) {
			ColonizationOrder@ order = colonization[i];
			
			//Remove invalid colonization orders
			if(order.target is null || !order.target.valid) {
				colonization.removeAt(i);
				obj.owner.unregisterColonization(obj, order.target);
				--i; --cnt;
				continue;
			}
			
			if(INSTANT_COLONIZE) {
				order.target.colonyShipArrival(obj.owner, 1.0);
				colonization.removeAt(i);
				obj.owner.unregisterColonization(obj, order.target);
				--i; --cnt;
				continue;
			}
			
			Empire@ owner = obj.owner;
			Empire@ otherOwner = order.target.owner;
			bool targetVisible = owner is otherOwner || order.target.isVisibleTo(owner);
			
			//Also remove colonization orders that are directed at colonies owned by foreign empires
			// but only if we can see the target
			if(otherOwner.valid && otherOwner !is obj.owner && targetVisible) {
				colonization.removeAt(i);
				obj.owner.unregisterColonization(obj, order.target);
				deltaCol = true;
				--i; --cnt;
				continue;
			}
			
			double targPop = targetVisible ? order.target.population : 0.0;
			if(targPop >= order.targetPopulation) {
				//Colonization is actually complete
				colonization.removeAt(i);
				obj.owner.unregisterColonization(obj, order.target);
				--i; --cnt;
				deltaCol = true;
				continue;
			}

			if(targPop + order.inTransit < order.targetPopulation - 0.0001) {						
				bool canSend = false;
				if(order.totalSent < 1.0)
					canSend = true;
				else if(!needsPopulationForLevel)
					canSend = true;
				else {
					auto@ lv = getPlanetLevel(LevelChainId, ResourceLevel);
					canSend = Population - popPerShip >= lv.requiredPop;
				}
				if(canSend) {
					//Takes one minute to send 1B population
					colonyShipTimer += float(60.0 / (1.0 / popPerShip));
					Population -= popPerShip;
					order.inTransit += popPerShip;
					order.totalSent += popPerShip;

					createColonizer(obj, order.target, popPerShip, colonyshipAccel);

					deltaPop = true;
					isSending = true;
				}
				break;
			}
		}
		isSendingColonizers = isSending;
	}

	bool get_isBeingColonized(Player& pl, const Object& obj) {
		Empire@ emp = pl.emp;
		if(emp is null)
			return false;
		return ColonizingMask & emp.mask != 0;
	}
	
	bool isEmpireColonizing(Empire@ emp) const {
		if(emp is null)
			return false;
		return ColonizingMask & emp.mask != 0;
	}

	void setBeingColonized(Empire@ emp, bool value) {
		if(value)
			ColonizingMask |= emp.mask;
		else
			ColonizingMask &= ~emp.mask;
		if(emp is playerEmpire && icon !is null)
			icon.setBeingColonized(value);
		deltaRes = true;
	}

	void modColonyShipAccel(double amt) {
		if(amt > 1.0)
			colonyshipAccel += amt - 1.0;
		else
			colonyshipAccel -= (1.0 / amt) - 1.0;
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
		growthFactor *= getPlanetLevel(LevelChainId, min(Level,obj.primaryResourceLimitLevel)).popGrowth;
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
	
	uint get_colonyOrderCount() const {
		return colonization.length;
	}

	bool get_isSendingColonyShips() const {
		return isSendingColonizers;
	}

	void flagColonizing() {
		isSendingColonizers = true;
	}
	
	Object@ get_colonyTarget(uint index) const {
		uint count = colonization.length;
		if(index < count)
			return colonization[index].target;
		else
			return null;
	}
	
	bool hasColonyTarget(Object& other) const {
		for(uint i = 0, cnt = colonization.length; i < cnt; ++i)
			if(colonization[i].target is other)
				return true;
		return false;
	}
	
	void stopColonizing(Object& obj, Object& other) {
		for(uint i = 0, cnt = colonization.length; i < cnt; ++i) {
			if(colonization[i].target is other) {
				colonization.removeAt(i);
				obj.owner.unregisterColonization(obj, other);
				deltaCol = true;
				break;
			}
		}
	}
	
	void modIncomingPop(double amount) {
		incomingPop += amount;
		if(incomingPop < 0.0)
			incomingPop = 0.0;
	}
	
	double get_IncomingPop() {
		return incomingPop;
	}

	void reducePopInTransit(Object& target, double amount) {
		for(uint i = 0, cnt = colonization.length; i < cnt; ++i) {
			if(colonization[i].target is target) {
				colonization[i].inTransit -= amount;
				return;
			}
		}
	}

	void buildWithDefense(Object& obj, double time, double defense) {
		if(defense <= 0 || !obj.canGainSupports) {
			@defenseDesign = null;
			defenseLabor = -1.0;
			return;
		}

		if(defenseDesign is null) {
			@defenseDesign = getDefenseDesign(obj.owner, defense);
			if(defenseDesign is null)
				return;
		}

		if(defenseLabor < 0) {
			//Start the build
			defenseLabor = getLaborCost(defenseDesign, 1);
		}

		defenseLabor -= time * defense;
		if(defenseLabor <= 0) {
			//Build defense here
			defenseDesign.decBuilt(); //automatic built doesn't increment
			createShip(obj, defenseDesign, obj.owner, obj, false, true);

			defenseLabor = -1.0;
			@defenseDesign = null;
		}
	}
	
	void spawnDefenseShips(Object& obj, double totalLaborValue) {
		Empire@ owner = obj.owner;
		array<const Design@> designs;
		{
			set_int chosenDesigns;
			ReadLock lock(owner.designMutex);
			uint designCount = owner.designCount;
			for(uint i = 0; i < designCount; ++i) {
				const Design@ dsg = owner.designs[i];
				if(dsg.obsolete)
					continue;
				if(dsg.newest() !is dsg)
					continue;
				if(!dsg.hasTag(ST_Support))
					continue;
				if(dsg.hasTag(ST_HasMaintenanceCost))
					continue;
				@dsg = dsg.newest();
				if(chosenDesigns.contains(dsg.id))
					continue;
				chosenDesigns.insert(dsg.id);
				designs.insertLast(dsg);
			}
		}
		
		uint dsgCount = designs.length;
		if(dsgCount == 0)
			return;
		
		double cheapest = 0;
		array<double> costs(dsgCount);
		for(uint i = 0; i < dsgCount; ++i) {
			double cost = getLaborCost(designs[i], 1);
			costs[i] = cost;
			if(i == 0 || cost < cheapest)
				cheapest = cost;
		}
		
		while(totalLaborValue >= cheapest && totalLaborValue > 0) {
			bool spawnedAny = false;
			
			uint base = randomi(0,dsgCount-1);
			for(uint i = 0; i < dsgCount; ++i) {
				uint index = (i + base) % dsgCount;
				double cost = costs[index];
				if(cost <= totalLaborValue) {
					designs[index].decBuilt(); //automatic built doesn't increment
					createShip(obj, designs[index], owner, obj, detectLeader=false, free=true, forceLeader=true);
					spawnedAny = true;
					totalLaborValue -= cost;
				}
			}
			
			if(!spawnedAny)
				break;
		}
	}

	void takeoverPlanet(Object& obj, Empire@ newOwner, double supportRatio) {
		if(obj.owner is newOwner)
			return;

		//Conquer edict rewards
		if(newOwner !is null) {
			Empire@ prevOwner = obj.owner;
			Empire@ master = newOwner.SubjugatedBy;
			if(master !is null && master.getEdictType() == DET_Conquer) {
				if(master.getEdictEmpire() is prevOwner)
					giveRandomReward(newOwner, (double(Level)+1.0)*2.0);
			}
		}
		
		//Check for 'Capture Enemy Homeworld' achievement
		if(obj is obj.owner.Homeworld && !getCheatsEverOn()) {
			if(newOwner is playerEmpire)
				unlockAchievement("ACH_TAKE_HOMEWORLD");
			if(mpServer && newOwner.player !is null)
				clientAchievement(newOwner.player, "ACH_TAKE_HOMEWORLD");
		}

		//Take over the planet
		@obj.owner = newOwner;
		obj.takeoverFleet(newOwner, supportRatio);
		newOwner.recordEvent(stat::Planets, 1, obj.name);
	}

	void annex(Player& from, Object& obj, Empire@ forEmpire = null) {
		//Check that we're allowed to do this annex
		if(from != SERVER_PLAYER) {
			if(forEmpire is null)
				@forEmpire = from.emp;
			Empire@ fromEmp = from.emp;
			if(fromEmp is null || fromEmp !is forEmpire)
				return;
		}
		if(forEmpire is obj.owner || forEmpire is null)
			return;
		if(obj.owner is null || !obj.owner.valid)
			return;

		//Check that the loyalty is 0
		if(obj.getLoyaltyFacing(forEmpire) > 0)
			return;

		//Notify previous owner
		obj.owner.notifyWarEvent(obj, WET_LostPlanet);

		//Annex the planet
		obj.takeoverPlanet(forEmpire);
		forEmpire.modAttribute(EA_PlanetsConquered, AC_Add, 1.0);
	}

	void abandon(Object& obj) {
		if(obj.isContested)
			return;
		@obj.owner = defaultEmpire;
		Population = 0;
		calculatePopVars(obj);
		deltaPop = true;
	}

	void forceAbandon(Object& obj) {
		@obj.owner = defaultEmpire;
		Population = 0;
		calculatePopVars(obj);
		deltaPop = true;
	}
	
	void giveBasicIconVision(Object& obj, Empire@ emp) {
		for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i) {
			Empire@ e = getEmpire(i);
			if(e is emp) {
				int mem = iconMemory[i];
				mem &= 0xffff;
				
				uint resource = 0xfffe;
				if(obj.nativeResourceCount != 0) {
					const ResourceType@ type = getResource(obj.nativeResourceType[0]);
					resource = type.id;
				}
				
				mem |= resource << 16;
				iconMemory[i] = mem;
				if(emp is playerEmpire)
					updateIcon(obj);
				
				break;
			}
		}
	}

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
							!obj.exportEnabled || ((type.isMaterial(Level) || destination !is null)
							&& (destination is null || !destination.owner.valid || destination.owner is obj.owner)),
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

	void onManualResourceRemoved(Object& obj) {
		setResourceLevel(obj, obj.getResourceTargetLevel());
		updateDecayLevel(obj, 0.0, wasManual = true);
	}

	void addAffinity(uint aff) {
		affinities.insertLast(aff);
		deltaAff = true;
	}

	void removeAffinity(uint aff) {
		uint cnt = affinities.length;
		for(uint i = 0; i < cnt; ++i) {
			if(aff == affinities[i]) {
				affinities.removeAt(i);
				deltaAff = true;
				break;
			}
		}
	}

	uint getAffinitiesMatching(uint resource) {
		uint amt = 0;
		for(uint i = 0, cnt = affinities.length; i < cnt; ++i) {
			if(affinityHas(affinities[i], resource))
				amt += 1;
		}
		return amt;
	}

	void calculatePopVars(Object& obj) {
		double income = 0.0;
		double prevTotal = 0.0;
		double prevPop = 0.0;
		double pop = Population;
		if(pop > double(maxPopulation))
			pop = double(maxPopulation) + (pop - double(maxPopulation)) * obj.owner.OverpopulationBenefitFactor;
		uint prevCap = 0;
		double baseCap = 0.0;
		double loy = 0.0, prevLoy = 1.0;
		uint maxPlanetLevel = getMaxPlanetLevel(LevelChainId);

		uint nativeCnt = obj.nativeResourceCount;
		uint nativeLevel = 0;
		uint limitLevel = obj.primaryResourceLimitLevel;
		if(nativeCnt != 0) {
			auto@ type = getResource(obj.nativeResourceType[0]);
			if(type !is null)
				nativeLevel = type.level;
		}
		float nativeLevelPct = 0.f;

		for(uint i = 0; i <= maxPlanetLevel && pop > 0; ++i) {
			const PlanetLevel@ level = getPlanetLevel(LevelChainId, i);

			double levelPop = level.population;
			double popDiff = levelPop - prevPop;
			double popFactor = min(pop / popDiff, 1.0);
			int lvIncome = level.baseIncome;

			if(nativeLevel == i)
				nativeLevelPct = popFactor;
			if(i <= limitLevel)
				lvIncome += level.resourceIncome;
			if(Level == 0 && i != 0)
				popFactor = 0.0;

			//Calculate base pressure
			double capDiff = level.basePressure - prevCap;
			baseCap += popFactor * capDiff;

			//Calculate base income
			double incDiff = lvIncome - prevTotal;
			income += popFactor * incDiff;

			//Calculate base loyalty
			if(i <= Level) {
				double loyDiff = level.baseLoyalty - prevLoy;
				loy += popFactor * loyDiff;
			}

			pop -= popDiff;
			prevTotal = lvIncome;
			prevPop = level.population;
			prevCap = level.basePressure;
			prevLoy = level.baseLoyalty;
		}

		if(pop > 0) {
			const PlanetLevel@ level = getPlanetLevel(LevelChainId, maxPlanetLevel);
			baseCap += pop * 3.0;
			income +=  pop * 30.0;
		}

		int newLoy = max(int(loy), 1);
		if(newLoy != prevBaseLoyalty) {
			modBaseLoyalty(obj, newLoy - prevBaseLoyalty);
			prevBaseLoyalty = newLoy;
		}

		popIncome = income;
		if(needsPopulationForLevel)
			obj.resourceEfficiency = nativeLevelPct;
		else
			obj.resourceEfficiency = 1.f;

		int cap = int(round(baseCap * pressureCapFactor)) + pressureCapMod + obj.owner.GlobalPressureCap;
		if(nativeCnt > 0) {
			Object@ dest = obj.nativeResourceDestination[0];
			if(dest !is null && dest.owner is obj.owner && obj.nativeResourceUsable[0])
				cap -= int(getPlanetLevel(LevelChainId, nativeLevel).exportPressurePenalty);
		}
		grid.pressureCap = uint(max(cap, 0));

		int newPop = 0;
		if(Population < MaxPopulation)
			newPop = int(Population);
		else
			newPop = int(Population) + (Population - MaxPopulation) * obj.owner.OverpopulationBenefitFactor;
		if(prevPopulation != newPop) {
			obj.owner.modTotalPopulation(newPop - prevPopulation);
			prevPopulation = newPop;
		}
	}

	void modIncome(int amount) {
		bonusIncome += amount;
		deltaPop = true;
	}

	void setGraphicsFlag(Object& obj, uint flag, bool value) {
		uint newValue = gfxFlags;
		if(value)
			newValue |= flag;
		else
			newValue &= ~flag;
		if(newValue != gfxFlags) {
			gfxFlags = newValue;
			deltaRes = true;

			PlanetNode@ plNode = cast<PlanetNode>(obj.getNode());
			if(plNode !is null)
				plNode.flags = gfxFlags;
		}
	}

	uint get_planetGraphicsFlags() const {
		return gfxFlags;
	}

	float occTimer = 0.f;
	void surfaceTick(Object& obj, double time) {
		//Set icon visibility
		if(icon !is null) {
			icon.visible = obj.isVisibleTo(playerEmpire);
			icon.hintParentObject(obj.region, false);
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

		//Grow population over time
		double localMax = double(MaxPopulation);
		if(overpopulation > 0)
			localMax += double(overpopulation);
		grid.localMax = localMax;

		if(Population >= 0.9999 && Population < localMax && bombardDecay <= 0 && MaxPopulation > 1) {
			double growthFactor = growthRate;
			if(Quarantined != 0)
				growthFactor = 0;
			float debtFactor = obj.owner.DebtFactor;
			for(; debtFactor > 0; debtFactor -= 1.f)
				growthFactor *= 0.33f + 0.67f * (1.f - min(debtFactor, 1.f));
			if(needsPopulationForLevel)
				growthFactor *= getPlanetLevel(LevelChainId, min(Level,obj.primaryResourceLimitLevel)).popGrowth / 60.0;
			else
				growthFactor *= getPlanetLevel(LevelChainId, Level).popGrowth / 60.0;
			growthFactor *= obj.owner.PopulationGrowthFactor;
			if(colonization.length != 0)
				growthFactor *= config::COLONIZING_GROWTH_PENALTY;
			if(obj.inCombat)
				growthFactor *= 0.1;
			Population = min(localMax, Population + growthFactor * time);
			calculatePopVars(obj);
			deltaPop = true;
		}
		else if(Population > localMax) {
			double decay = (1.0 / 60.0) * time * obj.owner.PopulationDecayFactor;
			Population = max(double(localMax), Population - decay);
			calculatePopVars(obj);
			deltaPop = true;
		}
		else if(bombardDecay > 0 && Population > 1.0) {
			double decay = (Population * 0.25 * double(bombardDecay) / 60.0) * time;
			Population = max(1.0, Population - decay);
			calculatePopVars(obj);
			deltaPop = true;
		}

		//Check if the resources should be enabled
		if(Population >= 0.9999) {
			if(!obj.areResourcesEnabled) {
				obj.enableResources();
				setBeingColonized(obj.owner, false);
			}
		}
		else {
			if(obj.areResourcesEnabled)
				obj.disableResources();
		}

		//Check planet level based on resources
		uint mod = obj.resourceModID;
		if(mod != ResourceModID) {
			ResourceModID = mod;
			setResourceLevel(obj, obj.getResourceTargetLevel());
			updateIcon(obj);
			calculatePopVars(obj);
		}

		//Update pressures from resource component
		grid.totalPressure = obj.totalResourcePressure;
		for(uint i = 0; i < TR_COUNT; ++i) {
			float prev = grid.pressures[i];
			float newVal = obj.resourcePressure[i];
			if(prev != newVal) {
				grid.pressures[i] = newVal;
				grid.delta = true;
			}
		}

		//Update object loyalty
		occTimer += time;
		if(occTimer > 1.f) {
			updateLoyalty(obj, occTimer);
			occTimer = 0.f;
		}
		Region@ reg = obj.region;
		if(siegeMask != 0 && reg !is null) {
			reg.SiegedMask |= obj.owner.mask;
			reg.SiegingMask |= siegeMask;
		}

		//Do level decay
		updateDecayLevel(obj, time);

		//Update stuff on the surface
		uint prevBuildings = grid.buildings.length;
		grid.tick(obj, time);
		if(prevBuildings != grid.buildings.length)
			++SurfaceModId;

		//Update resources from grid
		int newIncome = ceil(grid.resources[TR_Money] * TILE_MONEY_RATE * obj.owner.MoneyGenerationFactor) + popIncome + bonusIncome;
		if(prevIncome != newIncome) {
			if(prevIncome < 0) {
				if(newIncome < 0) {
					obj.owner.modMaintenance(-(newIncome - prevIncome), MoT_Planet_Upkeep);
				}
				else {
					obj.owner.modMaintenance(prevIncome, MoT_Planet_Upkeep);
					obj.owner.modTotalBudget(newIncome, MoT_Planet_Income);
				}
			}
			else {
				if(newIncome < 0) {
					obj.owner.modTotalBudget(-prevIncome, MoT_Planet_Income);
					obj.owner.modMaintenance(-newIncome, MoT_Planet_Upkeep);
				}
				else {
					obj.owner.modTotalBudget(newIncome - prevIncome, MoT_Planet_Income);
				}
			}
			prevIncome = newIncome;
		}

		double newEnergy = max(grid.resources[TR_Energy], 0.0);
		if(newEnergy != prevEnergy) {
			obj.owner.modEnergyIncome(double(newEnergy - prevEnergy) * TILE_ENERGY_RATE);
			prevEnergy = newEnergy;
		}

		double newInfluence = max(grid.resources[TR_Influence], 0.0);
		if(int(newInfluence) != int(prevInfluence)) {
			obj.owner.modInfluenceIncome(int(newInfluence) - int(prevInfluence));
			prevInfluence = newInfluence;
		}

		double newResearch = max(grid.resources[TR_Research], 0.0);
		if(newResearch != prevResearch) {
			obj.owner.modResearchRate(double(newResearch - prevResearch) * TILE_RESEARCH_RATE);
			prevResearch = newResearch;
		}

		double newDefense = max(grid.resources[TR_Defense], 0.0) * DEFENSE_LABOR_PM / 60.0 * obj.owner.DefenseGenerationFactor;
		bool pooled = obj.canGainSupports && obj.owner.hasDefending;
		if(!pooled) {
			if(prevDefense < -0.01) {
				prevDefense = -prevDefense;
				obj.owner.modDefenseRate(-prevDefense);
				obj.owner.modLocalDefense(newDefense);
			}

			buildWithDefense(obj, time, newDefense);
			if(newDefense != prevDefense) {
				obj.owner.modLocalDefense(newDefense - prevDefense);
				prevDefense = newDefense;
			}
		}
		else {
			if(prevDefense > 0.01) {
				obj.owner.modLocalDefense(-prevDefense);
				obj.owner.modDefenseRate(prevDefense);
				prevDefense = -prevDefense;
			}

			if(-newDefense != prevDefense) {
				obj.owner.modDefenseRate(newDefense - (-prevDefense));
				prevDefense = -newDefense;
			}
		}

		double prevLabor = obj.distributedLabor;
		double laborRes = max(grid.resources[TR_Labor], 0.0);
		double labor = laborRes * TILE_LABOR_RATE * obj.owner.LaborGenerationFactor;

		if(prevLabor != labor) {
			bool hasLabor = laborRes > 0.0001 || obj.laborIncome > 0.0001 || obj.currentLaborStored > 0.001;
			obj.canBuildShips = hasLabor;
			obj.canBuildAsteroids = hasLabor;
			obj.canBuildOrbitals = hasLabor;
			obj.canTerraform = hasLabor;
			obj.setDistributedLabor(labor);
		}

		//Apply colonization steps
		uint colCnt = colonization.length;
		if(colCnt != 0) {
			//Send colonization step when ready
			if(colonyShipTimer > 0)
				colonyShipTimer -= float(time);
			if(colonyShipTimer <= 0) {
				processColonization(obj);
				deltaPop = true;
			}
		}
		else {
			if(isSendingColonizers)
				deltaPop = true;
			isSendingColonizers = false;
		}

		//Deal with surface data grids
		if(reqSurfaceData)
			requestSurface(obj);
	}

	void _writePop(Message& msg) {
		int maxLevel = getLevelChain(LevelChainId).levels.length-1;
		msg.writeSmall(MaxPopulation);
		msg << float(Population);
		msg.writeSignedSmall(prevIncome);
		msg << Contestion;
		if(growthRate != 1.0) {
			msg.write1();
			msg << float(growthRate);
		}
		else {
			msg.write0();
		}
		msg.writeBit(needsPopulationForLevel);
		// Tell the client the LevelChainId before it tries to use it, fixes
		// bug where the client was reading the max level of a planet before
		// it found out the level chain of that planet. This meant that any
		// planet with a level chain that had a different max level to the
		// level chain with an id of 0 would be decoded incorrectly, and offset
		// the rest of the message by some number of bits, completely breaking
		// all decoding that followed. In the worst case, the broken decoding
		// would cause a Crash To Desktop as the PlanetNode tried to create
		// an Image with a ludicrous size, or the PlanetSurface tried to
		// create an array for a ludicrous grid size that ran out of memory.
		msg.writeLimited(LevelChainId,getLevelChainCount());
		msg.writeLimited(ResourceLevel,maxLevel);
		msg.writeBit(isSendingColonizers);
	}

	void _writeRes(Message& msg) {
		int maxLevel = getLevelChain(LevelChainId).levels.length-1;
		msg.writeLimited(LevelChainId,getLevelChainCount());
		msg.writeLimited(Level,maxLevel);
		if(DecayLevel < Level) {
			msg.write1();
			msg.writeLimited(DecayLevel,Level-1);
			msg << float(DecayTimer);
		}
		else {
			msg.write0();
		}

		if(maxPlanetLevel != -1) {
			msg.write1();
			msg.writeSmall(maxPlanetLevel);
		}
		else {
			msg.write0();
		}
		
		msg.writeBit(ColonizingMask != 0);
		if(ColonizingMask != 0)
			msg << ColonizingMask;
		
		msg << disableProtection;
		
		//TODO: This probably belongs somewhere else, but currently only changes when resources change
		if(abs(colonyshipAccel - 1.0) > 0.0001) {
			msg.writeBit(true);
			msg << float(colonyshipAccel);
		}
		else {
			msg.writeBit(false);
		}

		if(gfxFlags != 0) {
			msg.write1();
			msg.writeSmall(gfxFlags);
		}
		else {
			msg.write0();
		}
	}

	void _writeAff(Message& msg) {
		uint cnt = affinities.length;
		msg.writeSmall(cnt);
		for(uint i = 0; i < cnt; ++i)
			msg.writeSmall(affinities[i]);

		msg.writeSmall(Quarantined);
	}

	void clearProtectedFrom(uint mask = ~0) {
		uint prev = protectedFromMask;
		protectedFromMask &= ~mask;
		if(prev != protectedFromMask)
			deltaLoy = true;
	}

	void protectFrom(uint mask) {
		uint prev = protectedFromMask;
		protectedFromMask |= mask;
		if(prev != protectedFromMask)
			deltaLoy = true;
	}

	void _writeLoy(const Object& obj, Message& msg) {
		double base = double(BaseLoyalty + obj.owner.GlobalLoyalty.value);
		msg.writeSignedSmall(BaseLoyalty);
		msg.writeSignedSmall(LoyaltyBonus);
		msg.writeSmall(protectedFromMask);
		msg.writeSmall(orbitsMask);
		for(uint i = 0, cnt = getEmpireCount(); i < cnt; ++i) {
			double loy = LoyaltyEffect[i];
			if(loy == 0) {
				msg.write0();
			}
			else {
				msg.write1();
				msg.writeFixed(loy, -base, 0, 12);
			}
		}
	}
	
	void _writeColonization(Message& msg) {
		uint8 cnt = uint8(colonization.length);
		msg.writeBit(cnt != 0);
		if(cnt != 0) {
			msg << cnt;
			for(uint8 i = 0; i < cnt; ++i)
				msg << colonization[i].target;
		}
	}

	void _writeVis(Message& msg) {
		uint cnt = getEmpireCount();
		for(uint i = 0; i < cnt; ++i)
			msg << iconMemory[i];
	}

	bool writeSurfaceDelta(const Object& obj, Message& msg) {
		if(!deltaRes && !deltaAff && !deltaPop && !grid.delta && !deltaCol && !deltaLoy)
			return false;

		msg.write1();
		if(deltaRes) {
			deltaRes = false;
			msg.write1();
			_writeRes(msg);
		}
		else {
			msg.write0();
		}

		if(deltaAff) {
			deltaAff = false;
			msg.write1();
			_writeAff(msg);
		}
		else {
			msg.write0();
		}

		if(deltaPop) {
			deltaPop = false;
			msg.write1();
			_writePop(msg);
		}
		else {
			msg.write0();
		}

		if(grid.delta) {
			grid.delta = false;
			msg.write1();
			grid.write(msg, true);
		}
		else {
			msg.write0();
		}
		
		if(deltaCol) {
			deltaCol = false;
			msg.write1();
			_writeColonization(msg);
		}
		else {
			msg.write0();
		}
		
		if(deltaLoy) {
			deltaLoy = false;
			msg.write1();
			_writeLoy(obj, msg);
		}
		else {
			msg.write0();
		}

		return true;
	}

	void writeSurface(const Object& obj, Message& msg) {
		_writePop(msg);
		_writeRes(msg);
		_writeAff(msg);
		_writeLoy(obj, msg);
		_writeVis(msg);
		_writeColonization(msg);

		msg << Quarantined;
		msg << float(tileDevelopRate);
		msg << float(bldConstructRate);
		msg << float(undevelopedMaint);

		msg.writeSmall(originalSurfaceSize.x);
		msg.writeSmall(originalSurfaceSize.y);
		msg.writeSmall(biome0);
		msg.writeSmall(biome1);
		msg.writeSmall(biome2);

		grid.write(msg);
	}
}
