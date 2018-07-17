#pragma once
#include <network/address.h>
#include <network/message.h>
#include "threads.h"
#include <queue>

namespace net {

class MessageHandler;
class Transport {

	mutable threads::atomic_int references;
	threads::Mutex queueMutex;
	std::queue<std::pair<Message*,Address>> queuedSends;
	std::queue<std::pair<Message*,int>> queuedBroadcasts;

	int sockfd;
public:
	bool active;
	bool canBroadcast;
	AddressType type;

	int rate;

	Transport(AddressType Type = AT_IPv4);
	~Transport();

	void grab() const;
	void drop() const;

	void listen(Address& addr, bool rcvBroadcast = false);
	void process();

	void close();
	bool send(Message& msg, Address& adr, bool queue = true);
	bool broadcast(Message& msg, int port, bool queue = true);
	bool receive(Message& msg, Address& adr);

	static int RATE_LIMIT;

	friend class MessageHandler;
};
	
};
