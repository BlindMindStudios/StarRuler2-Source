import biomes;
import buildings;

enum SurfaceFlags {
	SuF_Usable = 1,
};

void preparePlanetShader(Object& obj) {
#section client
	vec4f picks;

	getBiomePicks(obj, getBiome(obj.Biome0), picks);
	shader::BIOME_PICKS[0] = picks;

	getBiomePicks(obj, getBiome(obj.Biome1), picks);
	shader::BIOME_PICKS[1] = picks;

	getBiomePicks(obj, getBiome(obj.Biome2), picks);
	shader::BIOME_PICKS[2] = picks;

	shader::PLANET_FULL_GRID_SIZE = vec2f(obj.surfaceGridSize);
	shader::PLANET_SURFACE_GRID_SIZE = vec2f(obj.originalGridSize);
#section all
}

void getBiomePicks(Object& obj, const Biome@ biome, vec4f& picks) {
	if(biome is null)
		return;
	picks = biome.picks;
	picks.z += (biome.lookupRange.y - biome.lookupRange.x) * double((obj.id * 2654435761) % 127) / 127.0 + biome.lookupRange.x;
}

void renderSurfaceData(Object& obj, PlanetSurface& surface, Image& output, const vec2u& sizeLimit = vec2u(0,0), bool citiesMode = false) {
	Image@ img = output;
	vec2u size = surface.size;
	vec2u origSize = vec2u(obj.originalGridSize);
	if(sizeLimit.x != 0 && sizeLimit.y != 0)
		size = sizeLimit;
	if(img.size != size)
		@img = Image(size, 4);

	const Biome@ biome0;
	const Biome@ biome1;
	const Biome@ biome2;

	if(surface.biomes.length == 1) {
		@biome0 = getBiome(obj.Biome0);
	}
	else if(surface.biomes.length == 2) {
		@biome0 = getBiome(obj.Biome0);
		@biome1 = getBiome(obj.Biome1);
	}
	else if(surface.biomes.length >= 3) {
		@biome0 = getBiome(obj.Biome0);
		@biome1 = getBiome(obj.Biome1);
		@biome2 = getBiome(obj.Biome2);
	}

	for(uint y = 0; y < size.height; ++y) {
		for(uint x = 0; x < size.width; ++x) {
			const Biome@ biome = surface.getBiome(x, y);

			Color output(0);
			if(x >= origSize.x || y >= origSize.y) {
				if(biome.isMoon) {
					output.r = 0xff;
				}
				else if(biome.isVoid) {
					//output.a = 0; //implied
				}
				else {
					output.g = 0xff;
				}
			}
			else {
				output.b = 0x80;
				if(citiesMode) {
					if(surface.getBuilding(x, y) !is null)
						output.a = 0xff;
					else
						output.a = 0x0;
				}
				else {
					output.a = 0xff;
				}

				if(biome.isCrystallic)
					output.b = 0;

				if(biome.isVoid) {
					output.a = 0;
				}
				else if(biome.isWater) {
					output.b = 0xff;
				}
				else if(biome is biome0) {
					//output.r = 0; //implied
					//output.g = 0; //implied
				}
				else if(biome is biome1) {
					output.r = 0xff;
					//output.g = 0; //implied
				}
				else if(biome is biome2) {
					//output.r = 0; //implied
					output.g = 0xff;
				}
			}

			img.set(x,y, output);
		}
	}

	if(img !is output)
		output = img;
}

class PlanetSurface : Serializable {
	vec2u size;

	//Data grid
	array<uint8> biomes;
	array<uint8> flags;
	array<SurfaceBuilding@> tileBuildings;
	const Biome@ baseBiome;

	//Resources and pressures
	double[] resources = double[](TR_COUNT, 0);
	float[] saturates = float[](TR_COUNT, 0);
	float[] pressures = float[](TR_COUNT, 0.f);
	double totalResource = 0;
	float totalSaturate = 0;
	double totalPressure = 0.0;

	//Improving tiles to usable status
	vec2u nextReady;
	double readyTimer = -1.0;
	int Maintenance = 0;
	uint usableTiles = 0;
	uint citiesBuilt = 0;
	uint civsBuilt = 0;
	uint pressureCap = 0;

	//Civilian building construction
	array<SurfaceBuilding@> buildings;
	SurfaceBuilding@ civConstructing;

	PlanetSurface() {
	}

	uint get_dataSize() {
		return size.width * size.height;
	}
	
	bool isValidPosition(const vec2i& pos) const {
		return uint(pos.x) < size.width && uint(pos.y) < size.height;
	}
	
	bool isValidPosition(const vec2u& pos) const {
		return pos.x < size.width && pos.y < size.height;
	}

	void clearState() {
		for(uint i = 0, cnt = flags.length; i < cnt; ++i)
			flags[i] = 0;
		for(uint i = 0, cnt = flags.length; i < cnt; ++i)
			@tileBuildings[i] = null;
		buildings.length = 0;
	}
	
	void write(Message& msg) {
		write(msg, false);
	}

	void write(Message& msg, bool delta) {
		msg.writeSmall(size.width);
		msg.writeSmall(size.height);

		msg << baseBiome.id;
		msg.writeSmall(Maintenance);
		msg.writeSmall(pressureCap);
		msg.writeSmall(civsBuilt);

		uint maxBiomeID = getBiomeCount() - 1;
		uint dsize = biomes.length;
		uint8 prevFlags = 0, prevBiome = baseBiome.id;
		for(uint i = 0; i < dsize; ++i) {
			uint8 biome = biomes[i];
			if(biome != prevBiome) {
				msg.write0();
				msg.writeLimited(biome,maxBiomeID);
				prevBiome = biome;
			}
			else {
				msg.write1();
			}
			
			uint8 _flags = flags[i];
			if(_flags != prevFlags) {
				msg.write0();
				msg << _flags;
				prevFlags = _flags;
			}
			else {
				msg.write1();
			}
		}

		uint bcnt = buildings.length;
		msg.writeSmall(bcnt);
		int civIndex = -1;
		for(uint i = 0; i < bcnt; ++i) {
			SurfaceBuilding@ bldg = buildings[i];
			if(bldg is civConstructing)
				civIndex = int(i);
			if(delta) {
				msg.writeBit(bldg.delta);
				if(!bldg.delta)
					continue;
				bldg.delta = false;
			}
			bldg.write(msg);
		}
		
		if(civIndex > 0) {
			msg.write1();
			msg.writeSmall(uint(civIndex));
		}
		else {
			msg.write0();
		}
		
		for(uint i = 0; i < TR_COUNT; ++i) {
			if(resources[i] != 0) {
				msg.write1();
				msg << float(resources[i]);
			}
			else {
				msg.write0();
			}
			
			if(pressures[i] != 0) {
				msg.write1();
				msg << pressures[i];
				msg << saturates[i];
			}
			else {
				msg.write0();
			}
		}
	}
	
	void read(Message& msg) {
		read(msg, false);
	}

	bool read(Message& msg, bool delta) {
		bool surfaceDelta = false;
		size.width = msg.readSmall();
		size.height = msg.readSmall();
		
		uint8 baseId = 0;
		msg >> baseId;
		@baseBiome = ::getBiome(baseId);
		Maintenance = msg.readSmall();
		pressureCap = msg.readSmall();
		civsBuilt = msg.readSmall();

		uint maxBiomeID = getBiomeCount() - 1;
		
		uint dsize = dataSize;
		if(biomes.length != dsize)
			surfaceDelta = true;
		biomes.length = dsize;
		flags.length = dsize;
		tileBuildings.length = dsize;
		
		uint8 prevFlags = 0, prevBiome = baseId;
		for(uint i = 0; i < dsize; ++i) {
			if(!msg.readBit())
				prevBiome = msg.readLimited(maxBiomeID);
			if(!surfaceDelta && prevBiome != biomes[i])
				surfaceDelta = true;
			biomes[i] = prevBiome;
			
			if(!msg.readBit())
				msg >> prevFlags;
			flags[i] = prevFlags;
			
			@tileBuildings[i] = null;
		}

		uint bcnt = msg.readSmall();
		buildings.length = bcnt;

		for(uint i = 0; i < bcnt; ++i) {
			if(buildings[i] is null)
				@buildings[i] = SurfaceBuilding();

			SurfaceBuilding@ bld = buildings[i];
			if(delta && !msg.readBit())
				continue;
			
			bld.read(msg);

			vec2u pos = bld.position;
			vec2u center = bld.type.getCenter();

			for(uint x = 0; x < bld.type.size.x; ++x) {
				for(uint y = 0; y < bld.type.size.y; ++y) {
					vec2u rpos = (pos - center) + vec2u(x, y);
					uint index = rpos.y * size.width + rpos.x;
					@tileBuildings[index] = bld;
				}
			}
		}

		if(msg.readBit()) {
			uint civIndex = msg.readSmall();
			if(civIndex < buildings.length)
				@civConstructing = buildings[civIndex];
		}
		else {
			@civConstructing = null;
		}
		
		totalPressure = 0;
		totalSaturate = 0;
		totalResource = 0;

		for(uint i = 0; i < TR_COUNT; ++i) {
			if(msg.readBit()) {
				float resource = 0;
				msg >> resource;
				resources[i] = resource;
				totalResource += resource;
			}
			else {
				resources[i] = 0;
			}
			
			if(msg.readBit()) {
				msg >> pressures[i];
				totalPressure += pressures[i];

				msg >> saturates[i];
				totalSaturate += saturates[i];
			}
			else {
				pressures[i] = 0;
			}
		}

		return surfaceDelta;
	}

	uint getIndex(int x, int y) {
		return y * size.width + x;
	}

	const Biome@ getBiome(int x, int y) {
		uint index = y * size.width + x;
		if(index >= biomes.length)
			return null;
		return ::getBiome(biomes[index]);
	}

	uint8 getFlags(int x, int y) {
		uint index = y * size.width + x;
		if(index >= flags.length)
			return 0;
		return flags[index];
	}
	
	bool checkFlags(int x, int y, uint8 f) {
		uint index = y * size.width + x;
		if(index >= flags.length)
			return false;
		return (flags[index] & f) == f;
	}

	void setFlags(int x, int y, uint8 f) {
		uint index = y * size.width + x;
		if(index >= flags.length)
			return;
		flags[index] = f;
	}

	void addFlags(int x, int y, uint8 f) {
		uint index = y * size.width + x;
		if(index >= flags.length)
			return;
		flags[index] |= f;
	}

	void removeFlags(int x, int y, uint8 f) {
		uint index = y * size.width + x;
		if(index >= flags.length)
			return;
		flags[index] &= ~f;
	}

	SurfaceBuilding@ getBuilding(int x, int y) {
		uint index = y * size.width + x;
		if(index >= tileBuildings.length)
			return null;
		return tileBuildings[index];
	}

	float getBuildingBuildWeight(int x, int y) {
		uint index = y * size.width + x;
		if(index >= tileBuildings.length)
			return 0;
		SurfaceBuilding@ bld = tileBuildings[index];
		if(bld is null)
			return 0;
		return bld.type.hubWeight;
	}

	void setBuilding(int x, int y, SurfaceBuilding@ bld) {
		uint index = y * size.width + x;
		if(index >= tileBuildings.length)
			return;
		@tileBuildings[index] = bld;
	}
};
