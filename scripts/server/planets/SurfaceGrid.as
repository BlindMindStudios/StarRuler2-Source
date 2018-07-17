import biomes;
import planets.PlanetSurface;
import saving;
import attributes;
from resources import MoneyType;

const bool WRAP_MAP = true;
const double MAP_DISTANCE_FACTOR = 0.8;
const uint MAP_TICK_TILES = 10;

const float ADJACENT_WEIGHT = 1.f;
const float DIAGONAL_WEIGHT = 0.3f;

const double CIV_BUILD_TIME = 25.0;
const double CITY_BUILD_TIME = 15.0;

tidy class SurfaceGrid : PlanetSurface {
	int emptyDeveloped = 0;
	int bldMaintenanceRefund = 0;
	int pressureCapTaken = 0;
	double civTimer = 0.0;
	double localMax = 0.0;
	double[] civResources = double[](TR_COUNT, 0);
	float[] civResourceMods = float[](TR_COUNT, 0.f);
	bool delta = false;

	SurfaceGrid() {
		super();
	}

	void save(SaveFile& msg) {
		msg << size;
		msg << usableTiles;
		msg << nextReady;
		msg << readyTimer;
		msg << totalPressure;
		msg << totalSaturate;
		msg << totalResource;
		msg << emptyDeveloped;
		msg << citiesBuilt;
		msg << civsBuilt;
		msg << pressureCap;
		msg << bldMaintenanceRefund;
		msg << pressureCapTaken;

		msg.writeIdentifier(SI_Biome, baseBiome.id);

		uint dsize = biomes.length;
		for(uint i = 0; i < dsize; ++i) {
			msg.writeIdentifier(SI_Biome, biomes[i]);
			msg << flags[i];
		}

		uint bcnt = buildings.length;
		msg << bcnt;
		int civIndex = -1;
		for(uint i = 0; i < bcnt; ++i) {
			if(buildings[i] is civConstructing)
				civIndex = int(i);
			buildings[i].save(msg);
		}
		msg << civIndex;

		for(uint i = 0; i < TR_COUNT; ++i) {
			msg << resources[i];
			msg << civResources[i];
			msg << civResourceMods[i];
			msg << pressures[i];
			msg << saturates[i];
		}

		msg << Maintenance;
	}

	void load(SaveFile& msg) {
		msg >> size;
		msg >> usableTiles;
		msg >> nextReady;
		msg >> readyTimer;
		msg >> totalPressure;
		msg >> totalSaturate;
		msg >> totalResource;
		msg >> emptyDeveloped;
		msg >> citiesBuilt;
		msg >> civsBuilt;
		msg >> pressureCap;
		msg >> bldMaintenanceRefund;
		if(msg >= SV_0114)
			msg >> pressureCapTaken;
		else
			pressureCapTaken = civsBuilt;

		
		uint8 baseId = msg.readIdentifier(SI_Biome);
		@baseBiome = ::getBiome(baseId);

		uint dsize = dataSize;
		biomes.length = dsize;
		flags.length = dsize;
		tileBuildings.length = dsize;
		for(uint i = 0; i < dsize; ++i) {
			biomes[i] = uint8(msg.readIdentifier(SI_Biome));
			msg >> flags[i];
			@tileBuildings[i] = null;
		}

		uint bcnt = 0;
		msg >> bcnt;
		buildings.length = bcnt;

		for(uint i = 0; i < bcnt; ++i) {
			if(buildings[i] is null)
				@buildings[i] = SurfaceBuilding();

			SurfaceBuilding@ bld = buildings[i];
			bld.load(msg);

			vec2u pos = bld.position;
			vec2u center = bld.type.getCenter();

			for(uint x = 0; x < bld.type.size.x; ++x) {
				for(uint y = 0; y < bld.type.size.y; ++y) {
					vec2u rpos = pos - (center - vec2u(x, y));
					uint index = rpos.y * size.width + rpos.x;
					@tileBuildings[index] = bld;
				}
			}
		}

		int civIndex = -1;
		msg >> civIndex;
		if(civIndex == -1)
			@civConstructing = null;
		else
			@civConstructing = buildings[civIndex];

		for(uint i = 0; i < TR_COUNT; ++i) {
			msg >> resources[i];
			msg >> civResources[i];
			msg >> civResourceMods[i];
			msg >> pressures[i];
			msg >> saturates[i];
		}

		msg >> Maintenance;
	}

	void create(int width, int height, const Biome@ base) {
		size.width = width;
		size.height = height;

		uint dsize = width * height;
		biomes.length = dsize;
		flags.length = dsize;
		tileBuildings.length = dsize;

		for(uint i = 0; i < dsize; ++i) {
			biomes[i] = base.id;
			flags[i] = 0;
		}
		@baseBiome = base;
	}

	void generateContinent(const Biome@ biome, bool doOverride = false) {
		if(biome is baseBiome && !doOverride)
			return;

		array<uint8> depth = array<uint8>(biomes.length, 255);
		int x = 0, y = 0;

		//Find a base biome spot
		int tries = 10;
		do {
			x = randomi(0, size.width - 1);
			y = randomi(0, size.height - 1);
		} while(biomes[y*size.width+x] != (doOverride ? biome.id : baseBiome.id) && --tries > 0);

		//Plop the first tile
		plop(biome, depth, x, y, 0, false);
	}

	void rotateFor(const Biome@ baseBiome) {
		//Try to rotate the planet up and down so we get the least cut-off view of the continents.

		//Horizontal rotation
		int bestLine = 0;
		double lineWeight = INFINITY;
		int w = size.width, h = size.height;
		for(int x = 0; x < w; ++x) {
			int leftX = (x-1+w)%w;
			double w = 0;
			for(int y = 0; y < h; ++y) {
				auto@ leftBiome = getBiome(leftX, y);
				auto@ rightBiome = getBiome(x, y);

				double cw = 1.0;
				cw *= leftBiome.useWeight;
				cw *= rightBiome.useWeight;
				if(leftBiome is rightBiome)
					cw *= 10.0 * leftBiome.useWeight;
				w += cw;
			}

			if(w < lineWeight) {
				lineWeight = w;
				bestLine = x;
			}
		}

		if(bestLine != 0) {
			array<uint8> pop(bestLine);
			for(int y = 0; y < h; ++y) {
				for(int i = 0; i < bestLine; ++i)
					pop[i] = biomes[getIndex(i, y)];
				for(int x = 0; x < w-bestLine; ++x)
					biomes[getIndex(x, y)] = biomes[getIndex(x+bestLine, y)];
				for(int x = w-bestLine; x < w; ++x)
					biomes[getIndex(x, y)] = pop[x - (w-bestLine)];
			}
		}

		//Vertical rotation
		bestLine = 0;
		lineWeight = INFINITY;
		for(int y = 0; y < h; ++y) {
			int leftY = (y-1+h)%h;
			double w = 0;
			for(int x = 0; x < w; ++x) {
				auto@ leftBiome = getBiome(x, leftY);
				auto@ rightBiome = getBiome(x, y);

				double cw = 1.0;
				cw *= leftBiome.useWeight;
				cw *= rightBiome.useWeight;
				if(leftBiome is rightBiome)
					cw *= 10.0 * leftBiome.useWeight;
				w += cw;
			}

			if(w < lineWeight) {
				lineWeight = w;
				bestLine = y;
			}
		}

		if(bestLine != 0) {
			array<uint8> pop(bestLine);
			for(int x = 0; x < w; ++x) {
				for(int i = 0; i < bestLine; ++i)
					pop[i] = biomes[getIndex(x, i)];
				for(int y = 0; y < h-bestLine; ++y)
					biomes[getIndex(x, y)] = biomes[getIndex(x, y+bestLine)];
				for(int y = h-bestLine; y < h; ++y)
					biomes[getIndex(x, y)] = pop[y - (h-bestLine)];
			}
		}
	}

	void plop(const Biome@ biome, array<uint8>@ depth, int x, int y, uint dist, bool secondary) {
		if(WRAP_MAP) {
			if(x < 0) x += size.width;
			if(uint(x) >= size.width) x -= size.width;
			if(y < 0) y += size.height;
			if(uint(y) >= size.height) y -= size.height;
		}
		else {
			if(x < 0) return;
			if(uint(x) >= size.width) return;
			if(y < 0) return;
			if(uint(y) >= size.height) return;
		}

		if(dist > 0) {
			if(randomd() > pow(MAP_DISTANCE_FACTOR, dist))
				return;
		}

		uint index = y*size.width + x;
		if(depth[index] > dist) {
			depth[index] = dist;
			biomes[index] = biome.id;
		}
		else if(secondary)
			return;
		else
			secondary = true;

		plop(biome, depth, x+1, y, dist+1, secondary);
		plop(biome, depth, x-1, y, dist+1, secondary);
		plop(biome, depth, x, y+1, dist+1, secondary);
		plop(biome, depth, x, y-1, dist+1, secondary);
	}

	float getUseWeight(int x, int y) {
		//We don't want to develop developed tiles
		if(checkFlags(x, y, SuF_Usable))
			return 0;
		
		float weight = 0;
		
		//Iterate over all nearby valid tiles
		for(int tile_x = max(x-1,-1), end_x = min(size.width, x+1); tile_x <= end_x; ++tile_x) {
			bool hAdjacent = tile_x == x;
			for(int tile_y = max(y-1,0), end_y = min(size.height-1, y+1); tile_y <= end_y; ++tile_y) {
				bool vAdjacent = tile_y == y;
				//Skip the tile we're considering
				if(hAdjacent && vAdjacent)
					continue;
				
				//Loop horizontally
				int realX = tile_x, realY = tile_y;
				if(realX == -1)
					realX = size.width-1;
				else if(realX == int(size.width))
					realX = 0;
				
				//Nearby usable tiles improves the desirability of the tile
				if(checkFlags(realX, tile_y, SuF_Usable)) {
					if(!hAdjacent && !vAdjacent)
						weight += DIAGONAL_WEIGHT;
					else
						weight += ADJACENT_WEIGHT;
				}
			}
		}

		//Biomes can modify the weight
		weight *= getBiome(x, y).useWeight;

		//Depending on how much free space we have, weight building development
		auto@ bld = getBuilding(x, y);
		if(bld !is null) {
			if(emptyDeveloped < 2)
				return 0.01f;
			if(bld.type.tileMaintainCost > 0)
				weight += 0.5f * emptyDeveloped;
		}
		
		return weight;
	}

	float getBuildWeight(int x, int y) {
		//Only consider tiles that can be built on
		if(!checkFlags(x, y, SuF_Usable))
			return 0;
		if(getBuilding(x, y) !is null)
			return 0;
		
		float weight = 0;
		
		//Iterate over all nearby valid tiles
		for(int tile_x = max(x-1,0), end_x = min(size.width-1, x+1); tile_x <= end_x; ++tile_x) {
			bool hAdjacent = tile_x == x;
			for(int tile_y = max(y-1,0), end_y = min(size.height-1, y+1); tile_y <= end_y; ++tile_y) {
				bool vAdjacent = tile_y == y;
				//Skip the tile we're considering
				if(hAdjacent && vAdjacent)
					continue;
				
				//Nearby tiles with buildings improve desirability
				if(!hAdjacent && !vAdjacent)
					weight += DIAGONAL_WEIGHT * getBuildingBuildWeight(tile_x, tile_y);
				else
					weight += ADJACENT_WEIGHT * getBuildingBuildWeight(tile_x, tile_y);
			}
		}
		
		weight *= getBiome(x, y).useWeight;
		return weight;
	}

	vec2u findSettleTile() {
		double totalWeight = 0;
		for(uint i = 0, cnt = biomes.length; i < cnt; ++i)
			totalWeight += ::getBiome(biomes[i]).useWeight;

		if(totalWeight != 0) {
			double rand = randomd(0, totalWeight);
			double sum = 0;
			for(uint i = 0, cnt = biomes.length; i < cnt; ++i) {
				float w = ::getBiome(biomes[i]).useWeight;
				sum += w;
				if(rand < sum)
					return vec2u(i % size.width, i / size.width);
			}
		}

		return vec2u(randomi(0, size.width - 1), randomi(0, size.height - 1));
	}

	vec2u findPotentialExpandTile() {
		//This can be slow as fuck because it happens
		//fairly rarely.
		//TODO: Expand to new random places occasionally

		double totalWeight = 0;
		for(uint y = 0; y < size.height; ++y)
			for(uint x = 0; x < size.width; ++x)
				totalWeight += getUseWeight(x, y);

		if(totalWeight != 0) {
			double rand = randomd(0, totalWeight);
			double sum = 0;
			for(uint y = 0; y < size.height; ++y) {
				for(uint x = 0; x < size.width; ++x) {
					float w = getUseWeight(x, y);
					if(w != 0) {
						sum += w;
						if(rand < sum)
							return vec2u(x, y);
					}
				}
			}
		}

		return findSettleTile();
	}

	vec2i findCivBuildTile() {
		//This can be slow as fuck because it happens
		//fairly rarely.

		double totalWeight = 0;
		for(uint y = 0; y < size.height; ++y)
			for(uint x = 0; x < size.width; ++x)
				totalWeight += getBuildWeight(x, y);

		if(totalWeight != 0) {
			double rand = randomd(0, totalWeight);
			double sum = 0;
			for(uint y = 0; y < size.height; ++y) {
				for(uint x = 0; x < size.width; ++x) {
					float w = getBuildWeight(x, y);
					if(w != 0) {
						sum += w;
						if(rand < sum)
							return vec2i(x, y);
					}
				}
			}
		}

		for(uint y = 0; y < size.height; ++y) {
			for(uint x = 0; x < size.width; ++x) {
				if(!checkFlags(x, y, SuF_Usable))
					continue;
				if(getBuilding(x, y) !is null)
					continue;
				return vec2i(x, y);
			}
		}

		return vec2i(-1, -1);
	}

	void prepExpand(Object& obj) {
		nextReady = findPotentialExpandTile();
		readyTimer = 60.0;
	}

	void colonize(Object& obj) {
		if(usableTiles > 0)
			return;

		//Find the first tile to make usable
		for(uint i = 0, cnt = obj.owner.ColonizeDevelopTiles; i < cnt; ++i) {
			vec2u start = findSettleTile();
			addFlags(start.x, start.y, SuF_Usable);
			usableTiles += 1;
			emptyDeveloped += 1;
		}

		//Start making stuff usable
		prepExpand(obj);

		delta = true;
	}

	void complete(Object& obj, SurfaceBuilding@ bld, bool notify = true) {
		bld.delta = true;
		delta = true;
		bld.type.complete(obj, bld);
		if(bld.type.cls == BC_City) {
			citiesBuilt += 1;
		}
		else if(bld.type.cls == BC_Civilian) {
			civsBuilt += 1;
			pressureCapTaken += bld.type.pressureCapTaken;
		}
		else if(notify) {
			obj.owner.notifyStructure(obj, bld.type.id);
			obj.owner.modAttribute(EA_ImperialBuildingsBuilt, AC_Add, 1.0);
		}
		
		for(uint i = 0; i < TR_COUNT; ++i) {
			resources[i] += bld.type.resources[i];
			totalResource += bld.type.resources[i];
			saturates[i] += bld.type.saturates[i];
			totalSaturate += bld.type.saturates[i];

			if(bld.type.civilian) {
				civResources[i] += bld.type.resources[i];
				resources[i] += bld.type.resources[i] * civResourceMods[i];
			}
		}
	}

	void destroy(Object& obj, SurfaceBuilding@ bld) {
		bld.delta = true;
		delta = true;
		if(bld.completion >= 1.f) {
			bld.type.remove(obj, bld);
			if(bld.type.cls == BC_City)
				citiesBuilt -= 1;
			else if(bld.type.cls == BC_Civilian) {
				civsBuilt -= 1;
				pressureCapTaken -= bld.type.pressureCapTaken;
			}
			for(uint i = 0; i < TR_COUNT; ++i) {
				if(!bld.disabled) {
					resources[i] -= bld.type.resources[i];
					totalResource -= bld.type.resources[i];
					if(bld.type.civilian) {
						civResources[i] -= bld.type.resources[i];
						resources[i] -= bld.type.resources[i] * civResourceMods[i];
					}
				}
				saturates[i] -= bld.type.saturates[i];
				totalSaturate -= bld.type.saturates[i];
			}
		}
	}

	void disable(Object& obj, SurfaceBuilding@ bld) {
		if(bld.disabled)
			return;
		bld.delta = true;
		bld.disabled = true;
		delta = true;
		for(uint i = 0; i < TR_COUNT; ++i) {
			resources[i] -= bld.type.resources[i];
			totalResource -= bld.type.resources[i];
			if(bld.type.civilian) {
				civResources[i] -= bld.type.resources[i];
				resources[i] -= bld.type.resources[i] * civResourceMods[i];
			}
		}
	}

	void enable(Object& obj, SurfaceBuilding@ bld) {
		if(!bld.disabled)
			return;
		bld.delta = true;
		bld.disabled = false;
		delta = true;
		for(uint i = 0; i < TR_COUNT; ++i) {
			resources[i] += bld.type.resources[i];
			totalResource += bld.type.resources[i];
			if(bld.type.civilian) {
				civResources[i] += bld.type.resources[i];
				resources[i] += bld.type.resources[i] * civResourceMods[i];
			}
		}
	}
	
	void _removeBuilding(SurfaceBuilding@ bldg) {
		uint i = 0;
		for(uint cnt = buildings.length; i < cnt; ++i) {
			if(buildings[i] is bldg) {
				buildings.removeAt(i);
				break;
			}
		}
		
		for(uint cnt = buildings.length; i < cnt; ++i)
			buildings[i].delta = true;
		delta = true;
	}

	void build(Object& obj, const BuildingType@ type, vec2i pos, bool spawnNow = false, bool develop = false, float spawnCompletion = 1.f) {
		if(!spawnNow && !type.canBuildOn(obj))
			return;
		vec2i center = vec2i(type.getCenter());

		//Check if this is a valid position		
		double costFactor = obj.owner.BuildingCostFactor;
		int buildCost = ceil(double(type.baseBuildCost) * costFactor);
		for(uint y = 0; y < type.size.y; ++y) {
			for(uint x = 0; x < type.size.x; ++x) {
				vec2i rpos = (pos - center) + vec2i(x, y);
				if(rpos.x < 0 || rpos.y < 0)
					return;
				if(rpos.x >= int(size.x) || rpos.y >= int(size.y))
					return;
				SurfaceBuilding@ cur = getBuilding(rpos.x, rpos.y);
				if(cur !is null && !cur.type.civilian)
					return;
				auto@ biome = getBiome(rpos.x, rpos.y);
				if(!biome.buildable)
					return;

				if(getFlags(rpos.x, rpos.y) & SuF_Usable == 0) {
					double amt = double(type.tileBuildCost) * biome.buildCost * costFactor;
					for(uint n = 0, ncnt = type.buildAffinities.length; n < ncnt; ++n) {
						auto@ aff = type.buildAffinities[n];
						if(aff.biome is biome)
							amt *= aff.factor;
					}
					buildCost += ceil(amt);
				}
			}
		}

		int cycle = -1;
		if(!spawnNow) {
			if(!type.consume(obj))
				return;
			cycle = obj.owner.consumeBudget(buildCost);
			if(cycle == -1) {
				type.reverseConsume(obj);
				return;
			}
		}

		SurfaceBuilding bld(type);
		bld.position = vec2u(pos);
		bld.delta = true;
		bld.cycle = cycle;
		bld.cost = buildCost;
		bld.type.startConstruction(obj, bld);

		buildings.insertLast(bld);

		//Set on all the positions
		for(uint y = 0; y < type.size.y; ++y) {
			for(uint x = 0; x < type.size.x; ++x) {
				vec2i rpos = (pos - center) + vec2i(x, y);

				SurfaceBuilding@ cur = getBuilding(rpos.x, rpos.y);
				if(cur !is null) {
					destroy(obj, cur);
					_removeBuilding(cur);
					if(civConstructing is cur)
						@civConstructing = null;
				}
				else {
					if(getFlags(rpos.x, rpos.y) & SuF_Usable != 0)
						emptyDeveloped -= 1;
					else if(develop)
						addFlags(rpos.x, rpos.y, SuF_Usable);
				}

				setBuilding(rpos.x, rpos.y, bld);
			}
		}

		if(spawnNow) {
			//Spawn the building completed right now
			bld.completion = spawnCompletion;
			if(spawnCompletion >= 1.f)
				complete(obj, bld, notify=false);
		}
		else if(type.buildInQueue) {
			obj.startBuildingConstruction(type.id, pos);
		}

		delta = true;
	}

	void setBuildingCompletion(Object& obj, const vec2i& pos, float progress) {
		auto@ bld = getBuilding(pos.x, pos.y);
		if(bld is null)
			return;

		bool wasComplete = bld.completion >= 1.f;
		bld.completion = progress;
		if(!wasComplete && bld.completion >= 1.f) {
			bld.completion = 1.f;
			complete(obj, bld);
		}
	}

	void destroyBuilding(Object& obj, vec2i pos, bool force = false, bool undevelop = false) {
		SurfaceBuilding@ bld = getBuilding(pos.x, pos.y);
		if(bld is null)
			return;
		if(!force && obj.isContested && bld.completion >= 1.f)
			return;
		if(!force && bld.type.civilian)
			return;
		if(!force && !bld.type.canRemove(obj))
			return;

		//Remove from all the positions
		vec2i center = vec2i(bld.type.getCenter());
		for(uint y = 0; y < bld.type.size.y; ++y) {
			for(uint x = 0; x < bld.type.size.x; ++x) {
				vec2i rpos = vec2i(bld.position) - (center - vec2i(x, y));

				SurfaceBuilding@ cur = getBuilding(rpos.x, rpos.y);
				if(cur is bld) {
					setBuilding(rpos.x, rpos.y, null);
					if(getFlags(rpos.x, rpos.y) & SuF_Usable != 0) {
						if(undevelop)
							removeFlags(rpos.x, rpos.y, SuF_Usable);
						else
							emptyDeveloped += 1;
					}
				}
			}
		}

		//Trigger removal
		destroy(obj, bld);
		_removeBuilding(bld);

		if(bld.completion < 1.f) {
			if(bld.cycle != -1)
				obj.owner.refundBudget(bld.cost, bld.cycle);
			if(bld.type.buildInQueue)
				obj.cancelBuildingConstruction(bld.type.id, vec2i(bld.position));
			bld.type.cancelConstruction(obj, bld);
		}

		if(civConstructing is bld)
			@civConstructing = null;

		delta = true;
	}

	double getBuildingDiff(const BuildingType@ type, const BuildingType@ remove = null) {
		double amt = 0.0;
		for(uint j = 0; j < TR_COUNT; ++j) {
			amt += type.saturates[j];
			if(remove !is null)
				amt -= remove.saturates[j];
		}
		return amt;
	}

	const BuildingType@ findBuildingToBuild(Object& obj, BuildingClass ctype, const BuildingType@ base = null) {
		//Construct the best civilian building
		double bestAmt = ctype == BC_City ? -1.0 : 0.0;
		const BuildingType@ best;
		float presAvail = pressureCap - float(pressureCapTaken);

		for(uint it = 0, bcnt = getBuildingTypeCount(), i = randomi(0, bcnt-1); it < bcnt; ++it & (i = (i+1) % bcnt)) {
			const BuildingType@ cur = getBuildingType(i);
			if(cur.cls != ctype)
				continue;
			if(cur.base !is base)
				continue;
			if(!cur.canBuildOn(obj))
				continue;
			if(cur.pressureCapTaken > presAvail)
				continue;

			double amt = 0.0;
			for(uint j = 0; j < TR_COUNT; ++j) {
				float avail = max(pressures[j] - saturates[j], 0.f);
				float sat = cur.saturates[j];

				if(sat > avail + 0.01f) {
					amt = -1.0;
					break;
				}

				amt += cur.saturates[j];
			}

			if(amt > bestAmt) {
				bestAmt = amt;
				@best = cur;
			}
		}

		return best;
	}

	void buildCivilian(Object& obj, const BuildingType@ type, vec2u pos) {
		SurfaceBuilding bld(type);
		bld.position = pos;
		bld.delta = true;
		bld.type.startConstruction(obj, bld);

		buildings.insertLast(bld);
		setBuilding(pos.x, pos.y, bld);
		@civConstructing = bld;
		emptyDeveloped -= 1;

		delta = true;
	}

	void buildCity(Object& obj) {
		if(emptyDeveloped == 0)
			return;
		if(obj.owner.ForbidCityConstruction != 0.0)
			return;

		vec2i pos = findCivBuildTile();
		if(pos.x < 0 || pos.y < 0)
			return;
		const BuildingType@ type = findBuildingToBuild(obj, BC_City);
		if(type !is null)
			buildCivilian(obj, type, vec2u(pos));

		delta = true;
	}

	void downgradeCivilian(Object& obj, SurfaceBuilding@ bld) {
		destroy(obj, bld);
		@bld.type = bld.type.base;
		complete(obj, bld);

		delta = true;
	}

	void destroyCivilian(Object& obj, SurfaceBuilding@ cur) {
		destroy(obj, cur);
		setBuilding(cur.position.x, cur.position.y, null);
		_removeBuilding(cur);
		if(civConstructing is cur)
			@civConstructing = null;
		emptyDeveloped += 1;

		delta = true;
	}

	void upgradeCivilian(Object& obj, SurfaceBuilding@ upgrade, const BuildingType@ upgradeTo) {
		upgrade.upgrading = true;
		upgrade.completion = 0.f;
		@upgrade.type = upgradeTo;
		@civConstructing = upgrade;

		delta = true;
	}

	bool optimizeForResource(Object& obj) {
		//Make sure we have space and cities to build
		if(emptyDeveloped <= 0 || pressureCapTaken >= int(pressureCap))
			return false;

		//Just find the building with the most resources we can build.
		const BuildingType@ best = findBuildingToBuild(obj, BC_Civilian);

		if(best !is null) {
			vec2i pos = findCivBuildTile();
			if(pos.x < 0 || pos.y < 0)
				return false;
			buildCivilian(obj, best, vec2u(pos));
			return true;
		}

		return false;
	}

	bool optimizeForPressure(Object& obj) {
		//Check if we can split any upgrade to get better ratio
		if(emptyDeveloped > 0 && pressureCapTaken < int(pressureCap)) {
			SurfaceBuilding@ downgrade;
			const BuildingType@ bestBuild;
			float ratio = 0.f;
			float presAvail = pressureCap - float(pressureCapTaken);

			for(uint i = 0, cnt = buildings.length; i < cnt; ++i) {
				SurfaceBuilding@ cur = buildings[i];
				if(cur.type.cls != BC_Civilian)
					continue;
				if(cur.type.base is null)
					continue;

				//Find the best building to build if we downgrade this.
				float curRatio = cur.type.totalResource / cur.type.totalSaturate;
				float newRes = cur.type.base.totalResource;
				float newSat = cur.type.base.totalSaturate;

				float bestRatio = curRatio;
				const BuildingType@ build;

				for(uint it = 0, bcnt = getBuildingTypeCount(), n = randomi(0, bcnt-1); it < bcnt; ++it & (n = (n+1) % bcnt)) {
					const BuildingType@ type = getBuildingType(n);
					if(type.base !is null)
						continue;
					if(type.cls != BC_Civilian)
						continue;
					if(!type.canBuildOn(obj))
						continue;
					if(type.pressureCapTaken - (cur.type.pressureCapTaken - cur.type.base.pressureCapTaken) > presAvail)
						continue;

					//Check if we have the pressures
					float newRatio = 0.f;
					for(uint j = 0; j < TR_COUNT; ++j) {
						float pres = pressures[j] - saturates[j];
						float sat = type.saturates[j] - (cur.type.saturates[j] - cur.type.base.saturates[j]);
						if(sat > pres) {
							newRatio = -1.f;
							break;
						}
					}
					if(newRatio == -1.f)
						continue;

					//Check if we get a better ratio per pressure
					newRatio = (type.totalResource + newRes) / (type.totalSaturate + newSat);
					if(newRatio > bestRatio) {
						bestRatio = newRatio;
						@build = type;
					}
				}

				if(build !is null && (bestRatio - curRatio) > ratio) {
					ratio = (bestRatio - curRatio);
					@downgrade = cur;
					@bestBuild = build;
				}
			}

			//Downgrade and build whatever gives us the better ratio
			if(downgrade !is null) {
				downgradeCivilian(obj, downgrade);

				vec2i pos = findCivBuildTile();
				if(pos.x < 0 || pos.y < 0)
					return false;
				buildCivilian(obj, bestBuild, vec2u(pos));
				return true;
			}
		}

		return false;
	}

	bool optimizeForPressureCap(Object& obj) {
		//Check if we can upgrade anything straight up
		{
			SurfaceBuilding@ upgrade;
			const BuildingType@ upgradeTo;
			float ratio = 0.f;
			float presAvail = pressureCap - float(pressureCapTaken);

			for(uint i = 0, cnt = buildings.length; i < cnt; ++i) {
				SurfaceBuilding@ cur = buildings[i];
				if(cur.type.cls != BC_Civilian)
					continue;
				if(cur.type.upgrades.length == 0)
					continue;

				float curRatio = cur.type.totalResource;

				const BuildingType@ upType;
				float bestRatio = curRatio;

				for(uint n = 0, bcnt = cur.type.upgrades.length; n < bcnt; ++n) {
					const BuildingType@ type = cur.type.upgrades[n];
					if(!type.canBuildOn(obj))
						continue;
					if(type.pressureCapTaken - cur.type.pressureCapTaken > presAvail)
						continue;

					//Check if we have the pressures
					float newRatio = 0.f;
					for(uint j = 0; j < TR_COUNT; ++j) {
						float pres = pressures[j] - saturates[j];
						float sat = type.saturates[j] - cur.type.saturates[j];
						if(sat > pres) {
							newRatio = -1.f;
							break;
						}
					}
					if(newRatio == -1.f)
						continue;

					newRatio = type.totalResource;
					if(newRatio > bestRatio) {
						bestRatio = newRatio;
						@upType = type;
					}
				}

				if(upType !is null && (bestRatio - curRatio) > ratio) {
					ratio = (bestRatio - curRatio);
					@upgrade = cur;
					@upgradeTo = upType;
				}
			}

			if(upgrade !is null) {
				upgradeCivilian(obj, upgrade, upgradeTo);
				return true;
			}
		}

		//Check if we can demolish any building to upgrade
		//another one for better population ratio.
		{
			SurfaceBuilding@ demolish;
			SurfaceBuilding@ upgrade;
			const BuildingType@ upgradeTo;
			float ratio = 1.001f;
			float presAvail = pressureCap - float(pressureCapTaken);

			for(uint i = 0, cnt = buildings.length; i < cnt; ++i) {
				SurfaceBuilding@ cur = buildings[i];
				if(cur.type.upgrades.length == 0)
					continue;
				if(cur.type.cls != BC_Civilian)
					continue;

				for(uint j = 0; j < cnt; ++j) {
					SurfaceBuilding@ sec = buildings[j];
					if(j == i)
						continue;
					if(sec.type.cls != BC_Civilian)
						continue;

					for(uint n = 0, bcnt = cur.type.upgrades.length; n < bcnt; ++n) {
						const BuildingType@ type = cur.type.upgrades[n];
						if(!type.canBuildOn(obj))
							continue;
						if(type.pressureCapTaken - cur.type.pressureCapTaken - sec.type.pressureCapTaken > presAvail)
							continue;

						//Check if we have the pressures
						float newRatio = 0.f;
						for(uint k = 0; k < TR_COUNT; ++k) {
							float pres = pressures[k] - saturates[k];
							float sat = type.saturates[k] - cur.type.saturates[k] - sec.type.saturates[k];
							if(sat > pres) {
								newRatio = -1.f;
								break;
							}
						}
						if(newRatio == -1.f)
							continue;

						float prevRatio = (cur.type.totalResource + sec.type.totalResource) / 2.0;
						newRatio = (type.totalResource + 1.0) / 2.0;
						newRatio /= prevRatio;
						if(newRatio > ratio) {
							ratio = newRatio;
							@upgrade = cur;
							@upgradeTo = type;
							@demolish = sec;
						}
					}
				}
			}

			if(upgrade !is null) {
				destroyCivilian(obj, demolish);
				upgradeCivilian(obj, upgrade, upgradeTo);
				return true;
			}
		}

		return false;
	}

	bool removeCities(Object& obj) {
		//Remove cities until we have equivalent to
		//our population.
		for(int i = buildings.length - 1; i >= 0; --i) {
			SurfaceBuilding@ cur = buildings[i];
			if(cur.type.cls != BC_City)
				continue;
			destroyCivilian(obj, cur);
			return true;
		}
		return false;
	}

	void removeBuildings(Object& obj) {
		//Remove the building that brings us closest
		//to our needed population with the least resources lost.
		SurfaceBuilding@ demolish;
		float loseAmt = FLOAT_INFINITY;

		for(int i = buildings.length - 1; i >= 0; --i) {
			SurfaceBuilding@ cur = buildings[i];
			if(cur.type.cls != BC_Civilian)
				continue;

			float amt = cur.type.totalResource;
			if(amt < loseAmt) {
				loseAmt = amt;
				@demolish = cur;
			}
		}

		if(demolish !is null)
			destroyCivilian(obj, demolish);
	}

	void removeForPressure(Object& obj) {
		//Remove the building that brings us closest
		//to our needed pressures with the least resources lost.
		SurfaceBuilding@ demolish;
		float loseRatio = FLOAT_INFINITY;

		for(int i = buildings.length - 1; i >= 0; --i) {
			SurfaceBuilding@ cur = buildings[i];
			if(cur.type.cls != BC_Civilian)
				continue;

			float lost = 0.f;
			float gained = 0.f;
			for(uint j = 0; j < TR_COUNT; ++j) {
				float sat = saturates[j];
				float pres = pressures[j];

				if(sat <= pres) {
					lost += cur.type.saturates[j];
				}
				else {
					float csat = cur.type.saturates[j];
					float pos = min(csat, sat - pres);

					gained += pos;
					lost += (csat - pos);
				}
			}

			if(gained > 0.f) {
				float ratio = (cur.type.totalResource + lost) / gained;
				if(ratio < loseRatio) {
					loseRatio = ratio;
					@demolish = cur;
				}
			}
		}

		if(demolish !is null)
			destroyCivilian(obj, demolish);
	}

	bool checkCivilianConstruction(Object& obj) {
		double pop = obj.population;
		double maxPop = max(localMax, pop);
		int maxBuildings = pressureCap;

		//Destruction
		if(citiesBuilt > uint(maxPop)) {
			if(removeCities(obj))
				return true;
		}

		if(pressureCapTaken > maxBuildings) {
			removeBuildings(obj);
			return true;
		}

		for(uint j = 0; j < TR_COUNT; ++j) {
			if(saturates[j] > pressures[j]) {
				removeForPressure(obj);
				return true;
			}
		}

		if(obj.owner.HasPopulation == 0.0)
			return true;

		//Construction
		if(citiesBuilt < uint(pop) && citiesBuilt <= civsBuilt) {
			//Build a city if we need one
			buildCity(obj);
			return true;
		}
		else {
			if(pressureCapTaken < maxBuildings) {
				if(totalSaturate < totalPressure) {
					//First try to build new buildings with our remaining
					//population, to get the max amount of resource.
					if(optimizeForResource(obj))
						return true;
				}

				//We have no pressure remaining, but we still have
				//pressure cap remaining, so optimize for pressure.
				if(optimizeForPressure(obj))
					return true;
			}
			if(totalSaturate < totalPressure) {
				if(pressureCapTaken + (totalPressure - totalSaturate) > maxBuildings
						|| emptyDeveloped == 0) {
					//Optimize the planet for pressure cap efficiency.
					// Our population is full and we still have pressure left.
					if(optimizeForPressureCap(obj))
						return true;
				}
			}

			if(citiesBuilt < uint(pop)) {
				//Build a city if we can have one
				buildCity(obj);
				return true;
			}
		}

		return false;
	}

	void developTiles(Object& obj, uint amount) {
		for(uint i = 0; i < amount; ++i) {
			addFlags(nextReady.x, nextReady.y, SuF_Usable);
			usableTiles += 1;
			if(getBuilding(nextReady.x, nextReady.y) is null)
				emptyDeveloped += 1;
			prepExpand(obj);
			delta = true;
		}
	}
	
	void destroyRandomTile(Object& obj, bool civilOnly) {
		vec2u offset = vec2u(randomi(0,size.width-1), randomi(0,size.height-1));
		for(uint tx = 0; tx < size.width; ++tx) {
			uint x = (tx + offset.x) % size.width;
			for(uint ty = 0; ty < size.height; ++ty) {
				uint y = (ty + offset.y) % size.height;
				
				if(getFlags(x,y) & SuF_Usable != 0) {
					auto@ b = getBuilding(x, y);
					if(b !is null && !b.type.civilian)
						continue;
					
					if(b !is null)
						destroyCivilian(obj, b);
					
					removeFlags(x, y, SuF_Usable);
					delta = true;
					return;
				}
			}
		}
	}

	void addSurfaceArea(const vec2i& addSize, array<uint8>& addBiomes, uint8 voidBiome = uint(-1), bool developed = false, bool vertical = false, const array<bool>@ devState = null) {
		array<uint8> oldBiomes = biomes;
		array<uint8> oldFlags = flags;
		array<SurfaceBuilding@> oldBuildings = tileBuildings;
		vec2u oldSize = size;
		if(voidBiome == uint(-1))
			voidBiome = baseBiome.id;
		delta = true;

		if(vertical) {
			size.y += addSize.y;
			size.x = max(size.x, addSize.x);

			biomes.length = size.x * size.y;
			flags.length = size.x * size.y;
			tileBuildings.length = size.x * size.y;

			uint offset = (size.x - addSize.x) / 2;

			for(uint y = 0; y < size.y; ++y) {
				for(uint x = 0; x < size.x; ++x) {
					uint newIndex = y * size.width + x;
					if(y < oldSize.y) {
						if(x < oldSize.x) {
							uint oldIndex = y * oldSize.width + x;
							biomes[newIndex] = oldBiomes[oldIndex];
							@tileBuildings[newIndex] = oldBuildings[oldIndex];
							flags[newIndex] = oldFlags[oldIndex];
						}
						else {
							biomes[newIndex] = voidBiome;
							@tileBuildings[newIndex] = null;
							flags[newIndex] = 0;
						}
					}
					else {
						if(x >= offset && x < uint(addSize.x)+offset) {
							uint addIndex = (y - oldSize.y) * addSize.width + (x - offset);
							biomes[newIndex] = addBiomes[addIndex];
							@tileBuildings[newIndex] = null;
							if((devState !is null && devState[addIndex]) || (developed && biomes[newIndex] != voidBiome)) {
								flags[newIndex] = SuF_Usable;
								emptyDeveloped += 1;
							}
							else {
								flags[newIndex] = 0;
							}
						}
						else {
							biomes[newIndex] = voidBiome;
							@tileBuildings[newIndex] = null;
							flags[newIndex] = 0;
						}
					}
				}
			}
		}
		else {
			size.x += addSize.x;
			size.y = max(size.y, addSize.y);

			biomes.length = size.x * size.y;
			flags.length = size.x * size.y;
			tileBuildings.length = size.x * size.y;

			uint offset = (size.y - addSize.y) / 2;

			for(uint x = 0; x < size.x; ++x) {
				for(uint y = 0; y < size.y; ++y) {
					uint newIndex = y * size.width + x;
					if(x < oldSize.x) {
						if(y < oldSize.y) {
							uint oldIndex = y * oldSize.width + x;
							biomes[newIndex] = oldBiomes[oldIndex];
							@tileBuildings[newIndex] = oldBuildings[oldIndex];
							flags[newIndex] = oldFlags[oldIndex];
						}
						else {
							biomes[newIndex] = voidBiome;
							@tileBuildings[newIndex] = null;
							flags[newIndex] = 0;
						}
					}
					else {
						if(y >= offset && y < uint(addSize.y)+offset) {
							uint addIndex = (y - offset) * addSize.width + (x - oldSize.x);
							biomes[newIndex] = addBiomes[addIndex];
							@tileBuildings[newIndex] = null;
							if(developed && biomes[newIndex] != voidBiome) {
								flags[newIndex] = SuF_Usable;
								emptyDeveloped += 1;
							}
							else {
								flags[newIndex] = 0;
							}
						}
						else {
							biomes[newIndex] = voidBiome;
							@tileBuildings[newIndex] = null;
							flags[newIndex] = 0;
						}
					}
				}
			}
		}
	}

	void tick(Object& obj, double time) {
		int maxPop = obj.maxPopulation;
		double pop = obj.population;

		//Tick expansion
		if(readyTimer > 0) {
			auto@ biome = getBiome(nextReady.x, nextReady.y);
			double rate = obj.tileDevelopmentRate * obj.owner.TileDevelopmentFactor / biome.buildTime;
			double targetTiles = (min(pop + 1.0, double(maxPop)) * 5.0 + double(pressureCap)) * rate;
			if(usableTiles >= uint(targetTiles))
				readyTimer -= time * rate / pow(1.4, (double(usableTiles) - targetTiles));
			else
				readyTimer -= time * rate * (targetTiles / double(usableTiles));

			if(readyTimer <= 0) {
				addFlags(nextReady.x, nextReady.y, SuF_Usable);
				usableTiles += 1;
				if(getBuilding(nextReady.x, nextReady.y) is null)
					emptyDeveloped += 1;
				prepExpand(obj);
				delta = true;
			}
		}

		//Deal with civilian construction
		if(civConstructing is null) {
			civTimer -= time;
			if(civTimer <= 0.0) {
				checkCivilianConstruction(obj);
				civTimer = randomd();
			}
		}
		else if(civConstructing.completion >= 1.f) {
			@civConstructing = null;
		}

		//Tick buildings
		uint chkRebuild = randomi(0, buildings.length - 1);
		double undevRate = obj.undevelopedMaintenance;

		int curMaintain = 0;
		for(uint i = 0, cnt = buildings.length; i < cnt; ++i) {
			SurfaceBuilding@ bld = buildings[i];

			//Check maintenance cost
			curMaintain += bld.type.baseMaintainCost;
			if(bld.type.tileMaintainCost != 0) {
				vec2i center = vec2i(bld.type.getCenter());
				for(uint y = 0; y < bld.type.size.y; ++y) {
					for(uint x = 0; x < bld.type.size.x; ++x) {
						vec2i rpos = vec2i(bld.position) - (center - vec2i(x, y));
						if(getFlags(rpos.x, rpos.y) & SuF_Usable == 0) {
							double amt = bld.type.tileMaintainCost * undevRate;
							for(uint n = 0, ncnt = bld.type.maintainAffinities.length; n < ncnt; ++n) {
								auto@ aff = bld.type.maintainAffinities[n];
								if(aff.biome is getBiome(rpos.x, rpos.y))
									amt *= aff.factor;
							}
							curMaintain += amt;
						}
					}
				}
			}

			//Handle construction of buildings
			if(bld.completion < 1.f) {
				if(bld.type.buildInQueue)
					continue;
				if(bld.type.civilian) {
					float pct = time * obj.buildingConstructRate * obj.owner.BuildingConstructRate * obj.owner.CivBldConstructionRate;
					if(bld.type.cls == BC_City) {
						pct /= CITY_BUILD_TIME;
						pct *= obj.owner.CityConstructRate;
					}
					else
						pct /= CIV_BUILD_TIME;
					float debtFactor = obj.owner.DebtFactor;
					for(; debtFactor > 0; debtFactor -= 1.f)
						pct *= 0.33f + 0.67f * (1.f - min(debtFactor, 1.f));
					bld.completion += pct;
				}
				else
					bld.completion += time * obj.buildingConstructRate * obj.owner.BuildingConstructRate / bld.type.getBuildTime(obj) * obj.owner.ImperialBldConstructionRate;
				bld.delta = true;
				
				if(bld.completion >= 1.f) {
					bld.completion = 1.f;
					if(bld.upgrading && bld.type.base !is null) {
						const BuildingType@ prev = bld.type;
						@bld.type = bld.type.base;
						destroy(obj, bld);
						@bld.type = prev;
					}
					complete(obj, bld);
				}

				delta = true;
				continue;
			}

			//Tick building stuff
			bld.type.tick(obj, bld, time);
			if(bld.delta)
				delta = true;
		}

		//Update maintenance cost
		curMaintain = curMaintain - bldMaintenanceRefund;
		if(Maintenance != curMaintain) {
			if(obj.owner !is null && obj.owner.valid)
				obj.owner.modMaintenance(max(curMaintain, 0) - max(Maintenance, 0), MoT_Buildings);
			Maintenance = curMaintain;
			delta = true;
		}
	}

	void gridChangeOwner(Object& obj, Empire@ prevOwner, Empire@ newOwner) {
		if(Maintenance > 0) {
			if(prevOwner !is null && prevOwner.valid)
				prevOwner.modMaintenance(-Maintenance, MoT_Buildings);
			if(newOwner !is null && newOwner.valid)
				newOwner.modMaintenance(+Maintenance, MoT_Buildings);
		}
		for(uint i = 0, cnt = buildings.length; i < cnt; ++i)
			buildings[i].type.ownerChange(obj, buildings[i], prevOwner, newOwner);
	}

	void gridDestroy(Object& obj) {
		if(Maintenance > 0) {
			if(obj.owner !is null && obj.owner.valid)
				obj.owner.modMaintenance(-Maintenance, MoT_Buildings);
		}
	}
};
