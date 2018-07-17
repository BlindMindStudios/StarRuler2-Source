#include "stat_history.h"

void StatEntry::addEvent(unsigned short type, const std::string& name) {
	StatEvent* newEvent = new StatEvent;
	newEvent->name = name;
	newEvent->type = type;

	if(!evt) {
		evt = newEvent;
	}
	else {
		newEvent->next = evt;
		evt = newEvent;
	}
}

StatHistory::StatHistory() : head(0), tail(0) {
}

StatEntry* StatHistory::addStatEntry(unsigned time) {
	if(tail && tail->time >= time) {
		return tail;
	}

	StatEntry* entry = new StatEntry;
	entry->time = time;

	if(tail) {
		tail->next = entry;
		entry->prev = tail;
		tail = entry;
	}
	else {
		head = entry;
		tail = entry;
	}

	return entry;
}

const StatEntry* StatHistory::getHead() const {
	return head;
}

StatEntry* StatHistory::getTail() const {
	return tail;
}