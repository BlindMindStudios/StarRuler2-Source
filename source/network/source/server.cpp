#include <network/server.h>

#ifdef __GNUC__
#include <netdb.h>
#include <sys/socket.h>
#elif defined(_MSC_VER)
#include <WS2tcpip.h>
#endif

namespace net {

Server::Server() : nextConnectionID(1) {
}

Server::Server(int port, const std::string& address, bool broadcast)
	: nextConnectionID(1) {
	listen(port, address, broadcast);
}

Server::~Server() {
	stop();
}

void Server::listen(int port, const std::string& address, bool broadcast) {
	struct addrinfo* res, *head;
	res = head = lookup(address, port);

	if(!res) {
		fprintf(stderr, "ERROR: Could not resolve hostname \"%s\".\n", address.c_str());
		return;
	}

	for(; res; res = res->ai_next) {
		if(res->ai_family != AF_INET && res->ai_family != AF_INET6)
			continue;

		Address addr;
		addr.from_sockaddr(*(sockaddr_storage*)res->ai_addr);

		Transport* transport = new Transport(addr.type);
		transport->listen(addr, broadcast);

		if(transport->active)
			addTransport(transport);

		transport->drop();

#ifdef __GNUC__
		//TODO: Figure out if this actually works.
		break;
#endif
	}

	freeaddrinfo(head);
}

void Server::connHandle(uint8_t type, Server::connMessageHandler func) {
	threads::Lock lock(handlerMutex);
	connHandlers[type] = func;
}

void Server::genHandle(uint8_t type, Server::genMessageHandler func) {
	threads::Lock lock(handlerMutex);
	genHandlers[type] = func;
}

void Server::connHandleClear(uint8_t type) {
	threads::Lock lock(handlerMutex);
	connHandlers.erase(type);
}

void Server::genHandleClear(uint8_t type) {
	threads::Lock lock(handlerMutex);
	genHandlers.erase(type);
}

void Server::send(int connId, Message& message) {
	if(connId < 0)
		sendAll(message);
	else
		*getConnectionByID(connId) << message;
}

void Server::sendAll(Message& message) {
	threads::Lock lock(connMutex);
	auto it = connections.begin(), end = connections.end();
	for(; it != end; ++it)
		*it->second << message;
}

void Server::doAll(connFunction func) {
	if(!func)
		return;
	threads::Lock lock(connMutex);
	auto it = connections.begin(), end = connections.end();
	for(; it != end; ++it)
		func(*it->second);
}

void Server::pingAll() {
	threads::Lock lock(connMutex);
	auto it = connections.begin(), end = connections.end();
	for(; it != end; ++it)
		it->second->sendPing();
}

Connection* Server::getConnectionByID(int id) {
	threads::Lock lock(connMutex);
	auto it = connectionIDs.find(id);
	if(it == connectionIDs.end())
		return 0;
	it->second->grab();
	return it->second;
}

void Server::kick(Connection& conn, DisconnectReason reason) {
	net::Message msg(MT_Disconnect);
	msg << reason;
	conn.send(msg, false);
	queueMessage(&conn.transport, conn.address, new Message(msg));
}

void Server::handleMessage(Transport* transport, Address addr, Message* msg) {
	//Find the connection that this address belongs to
	Connection* conn = 0;
	{
		threads::Lock lock(connMutex);
		auto it = connections.find(addr);
		if(it != connections.end()) {
			conn = it->second;
			conn->grab();
		}
	}

	//Handle the message
	uint8_t type = msg->getType();
	switch(type) {
		case MT_Disconnect:
			if(conn) {
				threads::Lock lock(connMutex);
				connections.erase(addr);
				connectionIDs.erase(conn->id);
				conn->active = false;
				conn->drop();
			}
		break;
		case MT_Connect:
			if(!conn) {
				conn = new Connection(*transport, addr);
				conn->id = nextConnectionID++;
				conn->grab();

				threads::Lock lock(connMutex);
				connections[addr] = conn;
				connectionIDs[conn->id] = conn;

				{
					Message response(MT_Connect, MF_Reliable);
					*conn << response;
				}
			}
		break;
	}

	//Send the message to the server handlers
	if(conn) {
		if(conn->preHandle(*this, msg)) {
			connMessageHandler handler = nullptr;
			{
				threads::Lock lock(handlerMutex);
				auto it = connHandlers.find(type);
				if(it != connHandlers.end())
					handler = it->second;
			}

			if(handler)
				handler(*this, *conn, *msg);

			conn->postHandle(*this, msg);
		}

		conn->drop();
	}
	else {
		genMessageHandler handler = nullptr;
		{
			threads::Lock lock(handlerMutex);
			auto it = genHandlers.find(type);
			if(it != genHandlers.end())
				handler = it->second;
		}

		if(handler)
			handler(*this, *transport, addr, *msg);
	}

	MessageHandler::handleMessage(transport, addr, msg);
}

bool Server::mainTick() {
	//Do normal message handler stuff
	bool received = MessageHandler::mainTick();

	//Let the connections process things
	{
		threads::Lock lock(connMutex);
		for(auto it = connections.begin(), end = connections.end(); it != end; ++it) {
			Connection* conn = it->second;

			if(!conn->active) {
				Message* msg = new Message(MT_Disconnect);
				if(conn->transport.active)
					*msg << DR_Timeout;
				else
					*msg << DR_Error;
				queueMessage(&conn->transport, conn->address, msg);
			}
			else {
				conn->process(*this);
			}
		}
	}

	return received;
}

void Server::stop() {
	if(active) {
		MessageHandler::stop();

		{
			threads::Lock lock(connMutex);
			for(auto it = connections.begin(), end = connections.end(); it != end; ++it)
				it->second->drop();
			connections.clear();
		}
	}
}
	
};
