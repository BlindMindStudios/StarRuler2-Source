#ifdef __GNUC__
#include <sys/socket.h>
#include <sys/select.h>
#elif defined(_MSC_VER)
#include <WS2tcpip.h>
#endif

#include <network/message_handler.h>
#include <network/init.h>

namespace net {

threads::threadreturn threadcall _mainLoop(void* data) {
	MessageHandler* handler = (MessageHandler*)data;
	if(handler->threadInit)
		handler->threadInit(true);

	while(handler->active) {
		if(!handler->mainTick())
			threads::sleep(NET_IDLE_SLEEP);
	}

	if(handler->threadExit)
		handler->threadExit(true);
	handler->threadsRunning.signalDown();
	return 0;
}

threads::threadreturn threadcall _queueLoop(void* data) {
	MessageHandler* handler = (MessageHandler*)data;
	if(handler->threadInit)
		handler->threadInit(false);

	while(handler->active) {
		if(!handler->queueTick())
			threads::sleep(NET_IDLE_SLEEP);
	}
	
	if(handler->threadExit)
		handler->threadExit(false);
	handler->threadsRunning.signalDown();
	return 0;
}

MessageHandler::MessageHandler()
	: active(true) {
}

void MessageHandler::queueMessage(Transport* transport, Address addr, Message* msg) {
	QueuedMessage q;
	q.transport = transport;
	q.addr = addr;
	q.msg = msg;

	transport->grab();

	{
		threads::Lock lock(queueMutex);
		messageQueue.push(q);
	}
}

void MessageHandler::handleMessage(Transport* transport, Address addr, Message* msg) {
	delete msg;
	transport->drop();
}

bool MessageHandler::queueTick() {
	if(messageQueue.empty())
		return false;

	queueMutex.lock();
	if(messageQueue.empty()) {
		queueMutex.release();
		return false;
	}

	QueuedMessage q = messageQueue.front();
	messageQueue.pop();
	queueMutex.release();

	handleMessage(q.transport, q.addr, q.msg);
	return true;
}

void MessageHandler::addTransport(Transport* transport) {
	threads::Lock lock(transportMutex);
	transport->grab();
	transports.push_back(transport);
}

void MessageHandler::clearTransports() {
	threads::Lock lock(transportMutex);
	for(auto it = transports.begin(); it != transports.end(); ++it)
		(*it)->drop();
	transports.clear();
}

bool MessageHandler::mainTick() {

	struct timeval timeout;
	bool received = false;

	//Populate the fd_set forselect
	fd_set polling;
	int nfds = 0;
	FD_ZERO(&polling);

	{
		threads::Lock lock(transportMutex);

		if(transports.empty())
			return false;

		for(auto it = transports.begin(), end = transports.end(); it != end;) {
			Transport* trans = *it;

			if(!trans->active) {
				it = transports.erase(it);
				end = transports.end();
				trans->drop();
				if(transports.empty())
					active = false;
			}
			else {
				//Process the transport
				trans->process();

				//Add the transport to the fd set
				int fd = trans->sockfd;
				FD_SET(fd, &polling);

				if(fd >= nfds)
					nfds = fd + 1;

				++it;
			}
		}
	}

	//Calculate the timeout
	timeout.tv_sec = NET_SELECT_TIMEOUT / 1000;
	timeout.tv_usec = (NET_SELECT_TIMEOUT % 1000) * 1000;

	int ready = select(nfds, &polling, 0, 0, &timeout);

	//Intercept errors
	if(ready < 0) {
#ifdef __GNUC__
		perror("Select error");
#else
		netError("Socket polling failed: ", WSAGetLastError());
#endif
		active = false;
		return true;
	}

	//Skip the rest if no transports are ready
	if(ready == 0)
		return false;

	//Read all messages that should be received
	{
		threads::Lock lock(transportMutex);

		for(auto it = transports.begin(), end = transports.end(); it != end; ++it) {
			Transport* trans = *it;

			Message msg;
			Address adr;

			while(trans->receive(msg, adr)) {
				Message* qmsg = new Message();
				msg.move(*qmsg);

				queueMessage(trans, adr, qmsg);
				received = true;
			}
		}
	}

	return received;
}

void MessageHandler::runThreads(int workerThreads) {
	if(workerThreads <= 0)
		throw "Threaded server needs at least one worker thread";

	threadsRunning.signal(workerThreads + 1);

	//Create a thread for the main connection loop
	threads::createThread(_mainLoop, this);

	//Create worker threads
	for(int i = 0; i < workerThreads; ++i)
		threads::createThread(_queueLoop, this);
}

void MessageHandler::stop() {
	if(active) {
		active = false;
		threadsRunning.wait(0);

		{
			threads::Lock lock(transportMutex);
			for(auto it = transports.begin(), end = transports.end(); it != end; ++it) {
				(*it)->close();
				(*it)->drop();
			}
			transports.clear();
		}
	}
}

MessageHandler::~MessageHandler() {
	stop();
}
	
};
