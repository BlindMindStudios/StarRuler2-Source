import icons;

enum TileResources {
	TR_Money,
	TR_Influence,
	TR_Energy,
	TR_Defense,
	TR_Labor,
	TR_Research,

	TR_COUNT,
	TR_NULL = TR_COUNT,
	TR_INVALID = TR_COUNT
};

enum AffinityMask {
	A_NULL = 0,
	A_Money = 1,
	A_Influence = 2,
	A_Energy = 4,
	A_Defense = 8,
	A_Labor = 16,
	A_Research = 32,

	A_ALL = 63,
};

TileResources getTileResource(string ident) {
	if(ident == "Money")
		return TR_Money;
	if(ident == "Influence")
		return TR_Influence;
	if(ident == "Energy")
		return TR_Energy;
	if(ident == "Defense")
		return TR_Defense;
	if(ident == "Labor")
		return TR_Labor;
	if(ident == "Research")
		return TR_Research;
	return TR_INVALID;
}

string getTileResourceIdent(uint r) {
	switch(r) {
		case TR_Money: return "Money";
		case TR_Influence: return "Influence";
		case TR_Energy: return "Energy";
		case TR_Defense: return "Defense";
		case TR_Labor: return "Labor";
		case TR_Research: return "Research";
	}
	return "-";
}

string getTileResourceSpriteSpec(uint r) {
	return getSpriteDesc(getTileResourceSprite(r));
}

const Sprite& getTileResourceSprite(uint r) {
	switch(r) {
		case TR_Money: return icons::Money;
		case TR_Influence: return icons::Influence;
		case TR_Energy: return icons::Energy;
		case TR_Defense: return icons::Defense;
		case TR_Labor: return icons::Labor;
		case TR_Research: return icons::Research;
	}
	return icons::Empty;
}

Color getTileResourceColor(uint r) {
	switch(r) {
		case TR_Money: return Color(0xd1cb6aff);
		case TR_Influence: return Color(0x0087c7ff);
		case TR_Energy: return Color(0x42b4bdff);
		case TR_Defense: return Color(0xaf7926ff);
		case TR_Labor: return Color(0xb1b4b6ff);
		case TR_Research: return Color(0x8c4ec9ff);
	}
	return Color();
}

string getTileResourceName(uint r) {
	switch(r) {
		case TR_Money: return locale::RESOURCE_MONEY;
		case TR_Influence: return locale::RESOURCE_INFLUENCE;
		case TR_Energy: return locale::RESOURCE_ENERGY;
		case TR_Defense: return locale::RESOURCE_DEFENSE;
		case TR_Labor: return locale::RESOURCE_LABOR;
		case TR_Research: return locale::RESOURCE_RESEARCH;
	}
	return "-";
}

Sprite getAffinitySprite(uint a) {
	if(a == A_ALL) {
		return Sprite(spritesheet::AffinityIcons, 11);
	}
	else if(a & A_Money != 0) {
		if(a & A_Energy != 0)
			return Sprite(spritesheet::AffinityIcons, 8);
		if(a & A_Influence != 0)
			return Sprite(spritesheet::AffinityIcons, 10);
		return Sprite(spritesheet::AffinityIcons, 0);
	}
	else if(a & A_Influence != 0) {
		if(a & A_Research != 0)
			return Sprite(spritesheet::AffinityIcons, 9);
		return Sprite(spritesheet::AffinityIcons, 1);
	}
	else if(a & A_Energy != 0) {
		if(a & A_Labor != 0)
			return Sprite(spritesheet::AffinityIcons, 7);
		else if(a & A_Defense != 0)
			return Sprite(spritesheet::AffinityIcons, 12);
		return Sprite(spritesheet::AffinityIcons, 2);
	}
	else if(a & A_Defense != 0) {
		if(a & A_Research != 0)
			return Sprite(spritesheet::AffinityIcons, 6);
		return Sprite(spritesheet::AffinityIcons, 3);
	}
	else if(a & A_Labor != 0) {
		return Sprite(spritesheet::AffinityIcons, 4);
	}
	else if(a & A_Research != 0) {
		return Sprite(spritesheet::AffinityIcons, 5);
	}
	return Sprite();
}

uint getPureAffinity(uint a) {
	if(a == A_Money)
		return TR_Money;
	if(a == A_Influence)
		return TR_Influence;
	if(a == A_Energy)
		return TR_Energy;
	if(a == A_Defense)
		return TR_Defense;
	if(a == A_Labor)
		return TR_Labor;
	if(a == A_Research)
		return TR_Research;
	return TR_NULL;
}

void splitAffinity(uint a, array<uint>& list) {
	if(a & A_Money != 0)
		list[TR_Money] += 1;
	if(a & A_Influence != 0)
		list[TR_Influence] += 1;
	if(a & A_Energy != 0)
		list[TR_Energy] += 1;
	if(a & A_Labor != 0)
		list[TR_Labor] += 1;
	if(a & A_Research != 0)
		list[TR_Research] += 1;
	if(a & A_Defense != 0)
		list[TR_Defense] += 1;
}

uint getAffinityFromDesc(const string& str) {
	if(str.trimmed() == "ALL")
		return A_ALL;
	array<string>@ types = str.split("+");
	uint aff = A_NULL;
	for(uint i = 0, cnt = types.length; i < cnt; ++i) {
		uint res = getTileResource(types[i].trimmed());
		if(res != TR_NULL)
			aff |= 1 << res;

	}
	return aff;
}

bool affinityHas(uint affinity, uint resource) {
	return affinity & (1<<resource) != 0;
}

string formatTileResources(const double[]@ resources, int size = 20) {
	string output = "";
	string sizeStr = toString(size, 0);
	for(uint i = 0, cnt = min(resources.length, TR_COUNT); i < cnt; ++i) {
		uint amt = resources[i];
		if(amt != 0) {
			string fmt = format("[img=$1;$2/]", getTileResourceSpriteSpec(TileResources(i)), sizeStr);
			for(uint j = 0; j < amt; ++j)
				output += fmt;
		}
	}
	return output;
}
