#pragma once
#include <network/message.h>
#include <network/client.h>
#include <network/server.h>
#include <unordered_map>
#include <set>
#include "threads.h"

namespace net {

#ifndef NET_LOBBY_HEARTBEAT_INTERVAL
#define NET_LOBBY_HEARTBEAT_INTERVAL 1000
#endif

#ifndef NET_LOBBY_HEARTBEAT_TIMEOUT
#define NET_LOBBY_HEARTBEAT_TIMEOUT 5000
#endif

#ifndef NET_LOBBY_QUERY_TIMEOUT
#define NET_LOBBY_QUERY_TIMEOUT 3000
#endif

enum LobbyMessage {
	LM_Heartbeat = MT_Application,
	LM_Query,
	LM_Result,
	LM_Results_End,
	LM_Identify,
};

enum LobbyFilterMode {
	LFM_Ignore,
	LFM_True,
	LFM_False,
};

struct Game {
	Address address;
	std::string name, mod;
	unsigned short players, maxPlayers;
	bool started, isLocal, password, listed;
	int punchPort, version;

	Game() : players(0), maxPlayers(0), started(false), isLocal(false), listed(true), password(false), punchPort(-1), version(0) {
	}
	void write(Message& msg);
	void read(Message& msg);
};

struct LobbyQuery {
	typedef std::function<void(Game&)> ResultHandler;

	Client client;
	BroadcastClient broadcast;
	int broadcastPort;
	ResultHandler handler;

	threads::Signal running;
	bool active;
	bool doUpdate;
	bool queryServer;
	bool queryBroadcast;

	std::set<Address> handled_lobbies;
	unsigned short receivedFromServer;
	unsigned short totalFromServer;

	LobbyQuery(Address ServerAddress, int BroadcastPort = -1);
	LobbyQuery(const std::string& hostname, int port, int BroadcastPort = -1, AddressType type = AT_IPv4);
	void bind();
	~LobbyQuery();

	LobbyFilterMode full, started;
	std::string name, mod;

	bool updating;
	void refresh(bool queryServer = true, bool queryBroadcast = true);
	void update(bool clear);
	void stop();
};

struct LobbyPunchthrough {
	Client* client;

	threads::Signal running;
	Address lobbyAddress;
	bool active;
	uint64_t interval;
	bool established;

	LobbyPunchthrough(Address ServerAddress, Client* client);
	void stop();
	void heartbeat();

	~LobbyPunchthrough();
};

struct LobbyHeartbeat : public Game {
	Client client;
	Transport* transport;
	Server broadcast;
	int broadcastPort;
	threads::Signal running;
	int fullCounter;
	bool active;
	uint64_t interval;

	bool identified;
	unsigned externalIP;
	unsigned short externalPort;

	LobbyHeartbeat(Address ServerAddress, int BroadcastPort = -1);
	void enablePunchthrough(Server* server);
	void run(bool doQuery = true, bool doBroadcast = true);
	void stop();
	void heartbeat();
	void identRequest();

	~LobbyHeartbeat();
};

struct LobbyServer {
	struct GameDesc : public Game {
		time lastHeartbeat;
	};

	Server server;
	threads::ReadWriteMutex mutex;
	threads::Signal running;
	std::map<Address, GameDesc> games;
	bool active, logging;

	LobbyServer(int port, const std::string& address = "", bool logging = true);
	void listen(int port, const std::string& address = "");

	void runThreads(int workerThreads = 4);
	void stop();

	~LobbyServer();
};

};
