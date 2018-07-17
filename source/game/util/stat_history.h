#pragma once
#include <string>

struct StatEvent {
	std::string name;
	StatEvent* next;
	unsigned short type;

	StatEvent() : type(0), next(0) {}
};

struct StatEntry {
	StatEntry* next, *prev;
	StatEvent* evt;
	unsigned time;

	union {
		int asInt;
		float asFloat;
	};

	void addEvent(unsigned short type, const std::string& name);

	StatEntry() : next(0), prev(0), time(0), evt(0), asInt(0) {}
};

class StatHistory {
	StatEntry* head, *tail;
public:

	StatHistory();

	StatEntry* addStatEntry(unsigned time);
	const StatEntry* getHead() const;
	StatEntry* getTail() const;
};