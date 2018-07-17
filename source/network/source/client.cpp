#include <network/client.h>
#include <network/init.h>

namespace net {

Client::Client(Address connectTo, bool makeConnection)
 : trans(new Transport(connectTo.type)), conn(0), address(connectTo),
	established(false), resolved(true), hasConnection(makeConnection) {
	if(makeConnection) {
		conn = new Connection(*trans, address);

		Message cmsg(MT_Connect, MF_Reliable);
		*this << cmsg;
	}

	if(trans->active)
		addTransport(trans);
}

Client::Client(const std::string& hostname, int port, bool makeConnection, AddressType type)
 : trans(new Transport(type)), conn(0), hostname(hostname), established(false),
	resolved(false), hasConnection(makeConnection) {
	address.port = port;
}

void Client::resolve() {
	threads::Lock lock(handlerMutex);
	if(!resolved) {
		address = net::Address(hostname, address.port);
		if(trans->active)
			addTransport(trans);

		if(hasConnection) {
			conn = new Connection(*trans, address);
			resolved = true;

			Message cmsg(MT_Connect, MF_Reliable);
			*this << cmsg;
		}
		else {
			resolved = true;
		}
	}
}

Client::~Client() {
	stop();
}

void Client::stop() {
	if(active) {
		if(conn) {
			Message dmsg(MT_Disconnect, MF_Reliable);
			dmsg << DR_Close;
			conn->send(dmsg, false);
		}

		MessageHandler::stop();

		if(conn) {
			conn->drop();
			conn = 0;
		}
	}
}

void Client::handle(uint8_t type, Client::clMessageHandler func) {
	threads::Lock lock(handlerMutex);
	handlers[type] = func;
}

void Client::handleClear(uint8_t type) {
	threads::Lock lock(handlerMutex);
	handlers.erase(type);
}

Client& Client::operator<<(Message& msg) {
	if(!resolved)
		resolve();
	if(conn)
		*conn << msg;
	else
		trans->send(msg, address);
	return *this;
}

void Client::sendPing() {
	if(conn)
		conn->sendPing();
}

unsigned Client::getLastPing() {
	if(conn)
		return conn->ping;
	return 0;
}

Connection* Client::getConnection() {
	return conn;
}

void Client::handleMessage(Transport* transport, Address addr, Message* msg) {
	uint8_t type = msg->getType();
	if(type == MT_Disconnect)
		active = false;
	if(conn) {
		if(type == MT_Connect)
			established = true;
		if(!conn->preHandle(*this, msg)) {
			MessageHandler::handleMessage(transport, addr, msg);
			return;
		}
	}

	clMessageHandler handler = nullptr;
	{
		threads::Lock lock(handlerMutex);
		auto it = handlers.find(type);
		if(it != handlers.end())
			handler = it->second;
	}

	if(handler)
		handler(*this, *msg);

	if(conn)
		conn->postHandle(*this, msg);

	MessageHandler::handleMessage(transport, addr, msg);
}

bool Client::mainTick() {
	//Resolve the address if we have to
	if(!resolved)
		resolve();

	//Do normal message handler stuff
	bool received = MessageHandler::mainTick();

	//Let the connection process things
	if(conn) {
		if(!conn->active) {
			{
				Message* dmsg = new Message(MT_Disconnect);
				if(trans->active)
					*dmsg << DR_Timeout;
				else
					*dmsg << DR_Error;

				trans->grab();
				handleMessage(trans, address, dmsg);
			}
			active = false;
		}
		else {
			conn->process(*this);
		}
	}

	return received;
}

BroadcastClient::BroadcastClient(int Port, AddressType Type)
	: trans(Type), port(Port) {

	if(trans.active)
		addTransport(&trans);
}

BroadcastClient::~BroadcastClient() {
	stop();
}

void BroadcastClient::handle(uint8_t type, BroadcastClient::bcMessageHandler func) {
	threads::Lock lock(handlerMutex);
	handlers[type] = func;
}

void BroadcastClient::handleClear(uint8_t type) {
	threads::Lock lock(handlerMutex);
	handlers.erase(type);
}

void BroadcastClient::handleMessage(Transport* transport, Address addr, Message* msg) {
	uint8_t type = msg->getType();

	bcMessageHandler handler = nullptr;
	{
		threads::Lock lock(handlerMutex);
		auto it = handlers.find(type);
		if(it != handlers.end())
			handler = it->second;
	}

	if(handler)
		handler(*this, addr, *msg);

	MessageHandler::handleMessage(transport, addr, msg);
}

void BroadcastClient::send(Message& msg, Address addr) {
	trans.send(msg, addr);
}

void BroadcastClient::broadcast(Message& msg) {
	trans.broadcast(msg, port);
}

};
