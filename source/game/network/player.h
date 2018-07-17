#pragma once
#include "network/address.h"

class Empire;
namespace net {
	class Connection;
	struct Sequence;
};

struct Player {
	int id;
	char nickname[32];
	Empire* emp;
	net::Address address;
	net::Connection* conn;
	net::Sequence* defaultSequence;
	bool hasGalaxy, wantsDeltas;
	bool changedEmpire;
	unsigned controlMask;
	unsigned viewMask;

	Player()
		: id(-1), emp(0), conn(0), defaultSequence(0), hasGalaxy(false), wantsDeltas(false), changedEmpire(false), controlMask(0), viewMask(0) {
		nickname[0] = '\0';
	}

	Player(int ID)
		: id(ID), emp(0), conn(0), defaultSequence(0), hasGalaxy(false), wantsDeltas(false), changedEmpire(false), controlMask(0), viewMask(0) {
		nickname[0] = '\0';
	}

	bool controls(Empire* emp);
	bool views(Empire* emp);
};
