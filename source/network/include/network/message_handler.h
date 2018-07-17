#pragma once
#include "threads.h"
#include <network/message.h>
#include <network/transport.h>
#include <queue>
#include <vector>
#include <functional>

namespace net {

#ifndef NET_SELECT_TIMEOUT
#define NET_SELECT_TIMEOUT 0
#endif

#ifndef NET_IDLE_SLEEP
#define NET_IDLE_SLEEP 1
#endif

class MessageHandler {
	struct QueuedMessage {
		Transport* transport;
		Address addr;
		Message* msg;
	};

	threads::Mutex queueMutex;
	threads::Mutex transportMutex;

	std::queue<QueuedMessage> messageQueue;
	std::vector<Transport*> transports;
public:
	threads::Signal threadsRunning;
	bool active;

	std::function<void(bool)> threadInit;
	std::function<void(bool)> threadExit;

	MessageHandler();
	virtual ~MessageHandler();

	void addTransport(Transport* transport);
	void clearTransports();

	virtual void queueMessage(Transport* transport, Address addr, Message* msg);
	virtual void handleMessage(Transport* transport, Address addr, Message* msg);

	virtual bool queueTick();
	virtual bool mainTick();

	virtual void runThreads(int workerThreads = 4);
	virtual void stop();
};
	
};
