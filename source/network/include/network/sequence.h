#pragma once
#include <network/message.h>
#include <network/client.h>
#include <network/message_handler.h>
#include <network/connection.h>
#include <network/time.h>
#include <unordered_map>
#include <unordered_set>

namespace net {

//Handles queueing and resending outgoing messages
struct OutSequence {
	Connection& conn;
	unsigned short id;
	unsigned short nextOutgoingID;
	unsigned short nextAck;
	unsigned resendPeriod;
	bool closed;

	struct MessageAwaitingAck {
		Message* msg;
		time lastResend;
		bool sent;
	};

	void queue(Message* mess);
	std::list<Message*> queuedMessages;
	std::unordered_set<unsigned short> waitingAcks;

	OutSequence(Connection& connection);

	void handleAck(unsigned short num);

	//Tries to pull a message from the sequence.
	// If it succeeds, the requester owns the message
	// Otherwise, returns a nullptr
	Message* getNextMessage();

	OutSequence& operator<<(Message& message);
	void close();
};

//Handles receiving and reordering incoming messages
struct InSequence {
	Connection& conn;
	unsigned short id;
	bool closed;

	std::unordered_map<unsigned short, Message*> unhandledMessages;
	unsigned short nextHandleID;
	unsigned short handlingID;

	InSequence(Connection& connection, unsigned short id);

	bool preHandle(MessageHandler& handler, Message* msg);
	void postHandle(MessageHandler& handler, Message* msg);
	void process(MessageHandler& handler, time& now);
};

//Wrapper class to easily create new outgoing sequences and
//close them when the wrapper goes out of scope
struct Sequence {
	OutSequence* ws;

	Sequence(Client& client);
	Sequence(Connection& connection);
	~Sequence();

	unsigned short id();
	Sequence& operator<<(Message& message);
};
	
};
