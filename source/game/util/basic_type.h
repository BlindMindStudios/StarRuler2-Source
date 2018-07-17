#pragma once

enum BasicTypes {
	BT_Int,
	BT_Double,
	BT_Bool
};

struct BasicType {
	BasicTypes type;
	union {
		int integer;
		double decimal;
		bool boolean;
	};
};