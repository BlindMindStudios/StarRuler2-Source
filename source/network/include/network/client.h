#pragma once
#include <network/message.h>
#include <network/message_handler.h>
#include <network/connection.h>
#include <functional>
#include <unordered_map>

namespace net {
struct LobbyHeartbeat;
struct LobbyPunchthrough;

/*
 * Client
 * ------
 * Connects to a server at an address, and handles incoming
 * messages from the server to the client.
 */

class Client : public MessageHandler {
public:
	typedef std::function<void(Client&,Message&)> clMessageHandler;
	Address address;
	bool established;

	std::string hostname;
	bool hasConnection;
	bool resolved;

	//Connect to the server on address, if makeConnection is true,
	//establish a connection, otherwise send only connectionless messages
	Client(Address connectTo, bool makeConnection = true);
	Client(const std::string& hostname, int port, bool makeConnection = true, AddressType type = AT_IPv4);
	~Client();

	//Handlers for any messages that are sent to this client
	void resolve();
	void handle(uint8_t type, clMessageHandler func);
	void handleClear(uint8_t type);

	//Send and get ping for the connection
	void sendPing();
	unsigned getLastPing();

	//Shortcut for sending messages to the server
	Client& operator<<(Message& msg);
	Connection* getConnection();

	//Overrides to add functionality to MessageHandler
	virtual void handleMessage(Transport* transport, Address addr, Message* msg);
	virtual bool mainTick();
	virtual void stop();
private:
	threads::Mutex handlerMutex;
	std::unordered_map<uint8_t, clMessageHandler> handlers;

	Transport* trans;
	Connection* conn;

	friend LobbyHeartbeat;
	friend LobbyPunchthrough;
};

/*
 * BroadcastClient
 * ---------------
 * Can broadcast messages and interact with replies to broadcasts.
 */
class BroadcastClient : public MessageHandler {
public:
	typedef std::function<void(BroadcastClient&,Address,Message&)> bcMessageHandler;
	
	//Connect to the server on address, if makeConnection is true,
	//establish a connection, otherwise send only connectionless messages
	BroadcastClient(int Port, AddressType Type = AT_IPv4);
	~BroadcastClient();

	//Handlers for any messages that are sent to this client
	void handle(uint8_t type, bcMessageHandler func);
	void handleClear(uint8_t type);

	//Send messages to an address over the transport
	void send(Message& msg, Address addr);

	//Broadcast messages on the port
	void broadcast(Message& msg);

	//Overrides to add functionality to MessageHandler
	virtual void handleMessage(Transport* transport, Address addr, Message* msg);
private:
	threads::Mutex handlerMutex;
	std::unordered_map<uint8_t, bcMessageHandler> handlers;

	int port;
	Transport trans;
};
	
};
