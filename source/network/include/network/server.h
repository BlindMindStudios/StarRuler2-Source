#pragma once
#include <network/message.h>
#include <network/message_handler.h>
#include <network/transport.h>
#include <network/connection.h>
#include <vector>
#include <map>
#include <unordered_map>
#include <functional>
#include "threads.h"

namespace net {

/*
 * Server
 * ------
 * Handles incoming connections and messages from
 * listening on one or multiple addresses/ports.
 */

class Server : public MessageHandler {
public:
	typedef std::function<void(Server&,Connection&,Message&)> connMessageHandler;
	typedef std::function<void(Server&,Transport&,Address,Message&)> genMessageHandler;
	typedef std::function<void(Connection&)> connFunction;

	Server();
	~Server();

	//Listen on everything associated with the passed address and port
	Server(int port, const std::string& address = "", bool broadcast = false);
	void listen(int port, const std::string& address = "", bool broadcast = false);

	//Handlers for messages that arrive on a specific connection
	void connHandle(uint8_t type, connMessageHandler func);
	void connHandleClear(uint8_t type);

	//Handlers for connection-less messages arriving on a transport
	void genHandle(uint8_t type, genMessageHandler func);
	void genHandleClear(uint8_t type);

	//Send to the connection with the given id
	void send(int connId, Message& message);

	//Send to all active connections
	void sendAll(Message& message);

	//Send a ping to all connected clients
	void pingAll();

	//Find the connection with the given id
	// NOTE: Grabs the connection before returning it
	Connection* getConnectionByID(int id);
	void doAll(connFunction func);

	//Kick a connection
	void kick(Connection& conn, DisconnectReason reason = DR_Kick);

	virtual void handleMessage(Transport* transport, Address addr, Message* msg);
	virtual bool mainTick();
	virtual void stop();
private:
	threads::Mutex connMutex;
	threads::Mutex handlerMutex;

	unsigned nextConnectionID;

	std::unordered_map<Address, Connection*> connections;
	std::unordered_map<int, Connection*> connectionIDs;

	std::unordered_map<uint8_t, connMessageHandler> connHandlers;
	std::unordered_map<uint8_t, genMessageHandler> genHandlers;
};

};
