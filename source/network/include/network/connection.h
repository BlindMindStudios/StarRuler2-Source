#pragma once
#include "threads.h"
#include <network/transport.h>
#include <network/address.h>
#include <network/time.h>
#include <unordered_map>
#include <unordered_set>
#include <list>
#include <deque>

namespace net {

#ifndef NET_RESEND_TIME
#define NET_RESEND_TIME 100
#endif

#ifndef NET_RESEND_RELIABLE_TIME
#define NET_RESEND_RELIABLE_TIME 250
#endif

#ifndef NET_RESEND_PERIOD
#define NET_RESEND_PERIOD 5
#endif

#ifndef NET_SEQUENCE_FUTURE
#define NET_SEQUENCE_FUTURE 100
#endif

#ifndef NET_PING_INTERVAL
#define NET_PING_INTERVAL 1000
#endif

#ifndef NET_PING_TIMEOUT
#define NET_PING_TIMEOUT 5000
#endif

#ifndef NET_FRAGMENT_LIMIT
#define NET_FRAGMENT_LIMIT 1000
#endif

#ifndef NET_FRAGMENT_OVERHEAD
#define NET_FRAGMENT_OVERHEAD 10
#endif

#ifndef NET_FRAGMENT_TIMEOUT
#define NET_FRAGMENT_TIMEOUT 5000
#endif

struct OutSequence;
struct InSequence;

struct SeqAck {
	unsigned short seqID;
	unsigned short msgID;
};
class Connection {
	//Connections can send messages reliable, that is,
	//messages with flag MF_Reliable set will be resent until
	//acknowledged by the other side
	struct MessageAwaitingAck {
		Message* msg;
		time lastResend;
	};

	mutable threads::atomic_int references;

	threads::Mutex ackMutex;
	std::unordered_set<unsigned short> queuedAcks;
	std::vector<SeqAck> queuedSeqAcks;

	threads::Mutex reliableMutex;
	std::list<Message*> queuedReliable;
	std::unordered_set<unsigned short> handledMessages;
	std::unordered_set<unsigned short> unorderedAcks;
	unsigned short nextOutgoingID;
	unsigned short nextAck;
	unsigned nextReliablePeriod;
	void handleAck(unsigned short id);

	bool split(Message& msg);
	void queueReliable(Message* msg, bool immediate = false);
	bool shouldHandleID(unsigned short id);

	threads::Mutex msgQueueLock;
	std::list<Message*> queuedMessages;
	void queue(Message* msg);

	struct WindowPacket {
		Message* msg;
		time added, sent;
	};
	
	threads::Mutex windowMutex;
	size_t windowBytes, windowUsed;
	double windowLength, windowUpdate;
	std::deque<WindowPacket> window;

	//Connections also have sequences of ordered, reliable messages
	threads::Mutex sequenceMutex;
	unsigned nextSequenceID;

	std::unordered_map<unsigned short, OutSequence*> outSequences;
	std::unordered_map<unsigned short, InSequence*> inSequences;

	//Connections handle message fragmentation transparently.
	//Messages over the fragment limit are sent in multiple parts without
	//any application interaction.
	threads::Mutex fragmentMutex;
	threads::atomic_int nextFragmentID;
	struct Fragment {
		std::vector<Message*> received;
		unsigned fragmentCount;
		time lastActivity;
	};
	std::unordered_map<unsigned, Fragment*> waitingFragments;
	void handleFragment(MessageHandler& handler, Message* msg);

	//Connections will keep themselves alive by pingponging, and time
	//out if we get no messages or responses to our pings for a certain
	//amount of time
	unsigned pingPongWait;
	time lastMessageReceived;
	time lastPingSent;
	time firstPingSent;
	bool pingSent;

	time lastProcessTime;
	unsigned outBytes, inBytes;

public:
	Transport& transport;
	bool active;
	Address address;
	int id;

	int availBytes;

	void grab() const;
	void drop() const;

	unsigned ping;
	void sendPing();

	bool preHandle(MessageHandler& handler, Message* msg);
	void postHandle(MessageHandler& handler, Message* msg);
	void process(MessageHandler& handler);

	//Returns the total amount of traffic in bytes since the last time getTraffic was called
	void getTraffic(unsigned& in_bytes, unsigned& out_bytes, unsigned& queuedPackets);

	OutSequence* sequence();
	void queueSeqAck(unsigned short sequenceID, unsigned short messageID);

	Connection(Transport& trans, Address addr);
	Connection& operator<<(Message& msg);
	//Sends a messsage through the pipe, immediately if possible
	// Returns true if the message should be considered sent
	bool send(Message& msg, bool isResend);
	~Connection();

	friend OutSequence;
};
	
};
