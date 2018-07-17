enum ContestedMode {
	CM_None,
	CM_Contested,
	CM_GainingLoyalty,
	CM_LosingLoyalty,
	CM_Protected,
	CM_Zealot,
};

const array<Color> ContestedColors = {
	Color(),
	Color(0xffc600ff),
	Color(0x38ff00ff),
	Color(0xff3800ff),
	Color(0x00c0ffff),
	Color(0xff00bfff)
};
