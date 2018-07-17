#include <network/lobby.h>
#include <network/time.h>
#include <time.h>
#include <stdio.h>
#include <stdarg.h>

namespace net {

void log(const char* format, ...) {
#ifdef __GNUC__
	va_list ap;
	va_start(ap, format);

	char line[2048];
	vsnprintf(line, 2048, format, ap);

	char date[2048];

	time_t t;
	::time(&t);
	struct tm tmp;
	localtime_r(&t, &tmp);
	strftime(date, 2048, "%d %b %Y %H:%M:%S", &tmp);

	printf("[%s] %s\n", date, line);
	fflush(stdout);
	va_end(ap);
#endif
}

void Game::write(Message& msg) {
	msg << name << mod;
	msg << players << maxPlayers;
	msg << address;
	msg << punchPort;
	msg.writeSmall(version);
	msg.writeBit(started);
	msg.writeBit(password);
	msg.writeBit(listed);
}

void Game::read(Message& msg) {
	msg >> name >> mod;
	msg >> players >> maxPlayers;
	msg >> address;
	msg >> punchPort;
	version = msg.readSmall();
	started = msg.readBit();
	password = msg.readBit();
	listed = msg.readBit();
	isLocal = false;
}

struct LobbyFilters {
	std::string name, mod;
	uint8_t full, started;
};

inline bool filterLobby(Game& desc, LobbyFilters& filters) {
	if(!filters.name.empty()) {
		if(desc.name.find(filters.name) == std::string::npos)
			return false;
	}

	if(!filters.mod.empty()) {
		if(desc.mod.find(filters.mod) == std::string::npos)
			return false;
	}

	switch(filters.full) {
		case LFM_True:
			if(desc.players != desc.maxPlayers)
				return false;
		break;
		case LFM_False:
			if(desc.players == desc.maxPlayers)
				return false;
		break;
	}

	switch(filters.started) {
		case LFM_True:
			if(!desc.started)
				return false;
		break;
		case LFM_False:
			if(desc.started)
				return false;
		break;
	}
	return true;
}

threads::threadreturn threadcall _heartbeatLoop(void* data) {
	LobbyHeartbeat* beat = (LobbyHeartbeat*)data;

	time timer, now;
	time_now(now);
	timer = now;

	while(beat->active) {
		time_now(now);
		if(time_diff(timer, now) >= beat->interval) {
			beat->heartbeat();
			timer = now;
		}
		threads::sleep(10);
	}

	beat->running.signalDown();
	return 0;
}

threads::threadreturn threadcall _identifyLoop(void* data) {
	LobbyHeartbeat* beat = (LobbyHeartbeat*)data;
	beat->identRequest();

	time timer, now;
	time_now(now);
	timer = now;

	while(beat->active && !beat->identified) {
		time_now(now);
		if(time_diff(timer, now) >= beat->interval) {
			beat->identRequest();
			timer = now;
		}
		threads::sleep(100);
	}

	beat->running.signalDown();
	return 0;
}

LobbyHeartbeat::LobbyHeartbeat(Address serverAddress, int Port)
	: client(serverAddress, false), broadcastPort(Port), identified(false), externalIP(0),
		externalPort(0), interval(NET_LOBBY_HEARTBEAT_INTERVAL), fullCounter(0), active(true) {

	broadcast.genHandle(LM_Query, [this](Server& srv, Transport& trans, Address addr, Message& mess) {
		//Read filters
		LobbyFilters filters;
		mess >> filters.name >> filters.mod;
		mess >> filters.full >> filters.started;

		//Apply filters
		if(!filterLobby(*this, filters))
			return;

		//Send result to requester
		Message msg(LM_Result);
		write(msg);

		trans.send(msg, addr);
	});

	client.handle(LM_Identify, [this](net::Client& cl, Message& msg) {
		identified = true;

		unsigned char type = 0;
		msg >> type;
		if(type == net::AT_IPv4) {
			msg >> externalIP;
			msg >> externalPort;
		}
		
		if(msg.hasError())
			externalIP = 0;
	});
}

void LobbyHeartbeat::enablePunchthrough(Server* server) {
	if(punchPort < 0)
		punchPort = 0;

	server->addTransport(client.trans);
	client.clearTransports();

	//Punchthrough messages should be redirected to open the port
	server->genHandle(MT_Punchthrough, [this](Server& srv, Transport& trans, Address adr, Message& msg) {
		if(&trans != client.trans)
			return;

		net::Address punchTo;
		msg >> punchTo;

		net::Message reply(MT_Punchthrough);
		trans.send(reply, punchTo);
	});

	server->genHandle(LM_Identify, [this](Server& srv, Transport& trans, Address adr, Message& msg) {
		identified = true;

		unsigned char type = 0;
		msg >> type;
		if(type == net::AT_IPv4) {
			msg >> externalIP;
			msg >> externalPort;
		}
		
		if(msg.hasError())
			externalIP = 0;
	});
}

void LobbyHeartbeat::run(bool doHeartbeat, bool doBroadcast) {
	if(doHeartbeat) {
		heartbeat();
		running.signalUp();
		threads::createThread(_heartbeatLoop, this);
	}

	if(doBroadcast && broadcastPort != -1) {
		broadcast.listen(broadcastPort, "", true);
		broadcast.runThreads(1);
	}

	running.signalUp();
	threads::createThread(_identifyLoop, this);
	client.runThreads(1);
}

void LobbyHeartbeat::stop() {
	if(active) {
		active = false;
		running.wait(0);
		client.stop();
		broadcast.stop();
	}
}

void LobbyHeartbeat::heartbeat() {
	Message msg(LM_Heartbeat);

	//Every 4 messages, send a full heartbeat
	if(fullCounter == 0) {
		msg.write1();
		write(msg);
	}
	else {
		msg.write0();
	}

	client << msg;
	fullCounter = (fullCounter + 1) % 4;
}

void LobbyHeartbeat::identRequest() {
	Message msg(LM_Identify);
	client << msg;
}

LobbyHeartbeat::~LobbyHeartbeat() {
	stop();
}


threads::threadreturn threadcall _punchthroughLoop(void* data) {
	LobbyPunchthrough* punch = (LobbyPunchthrough*)data;

	time timer, now;
	time_now(now);
	timer = now;

	while(punch->active) {
		time_now(now);
		if(time_diff(timer, now) >= punch->interval) {
			punch->heartbeat();
			timer = now;
		}
		threads::sleep(10);
	}

	punch->running.signalDown();
	return 0;
}

LobbyPunchthrough::LobbyPunchthrough(Address serverAddress, Client* cl)
	: interval(250), lobbyAddress(serverAddress),
			active(true), client(cl), established(false) {

	heartbeat();

	running.signalUp();
	threads::createThread(_punchthroughLoop, this);
}

void LobbyPunchthrough::stop() {
	active = false;
	running.wait(0);
}

void LobbyPunchthrough::heartbeat() {
	if(client) {
		if(!client->established && client->active) {
			net::Message req(MT_Punchthrough);
			net::Address reqAddr = client->address;
			req << reqAddr;
			client->trans->send(req, lobbyAddress);
		}
		else {
			active = false;
		}
	}
}

LobbyPunchthrough::~LobbyPunchthrough() {
	stop();
}

threads::threadreturn threadcall _serverLoop(void* data) {
	LobbyServer* srv = (LobbyServer*)data;
	time now;

	while(srv->active) {
		time_now(now);

		//Deactivate if the server goes down
		if(!srv->server.active) {
			srv->active = false;
			break;
		}

		//Prune all timed out games
		{
			threads::WriteLock lock(srv->mutex);
			auto it = srv->games.begin(), end = srv->games.end();
			while(it != end) {
				LobbyServer::GameDesc& desc = it->second;
				if(time_diff(desc.lastHeartbeat, now) > NET_LOBBY_HEARTBEAT_TIMEOUT) {
					if(srv->logging)
						log("[DD] Server \"%s\" timed out from %s. (comm port %d)",
								desc.name.c_str(), desc.address.toString().c_str(), it->first.port);
					it = srv->games.erase(it);
				}
				else
					++it;
			}
		}

		threads::sleep(500);
	}

	srv->running.signalDown();
	return 0;
}


LobbyServer::LobbyServer(int port, const std::string& address, bool Logging)
	: server(port, address), active(true), logging(Logging) {

	if(logging)
		log("[II] Starting master server on port %d", port);

	//Clients are constantly sending heartbeats, we track
	//all the active servers. Full heartbeats add timed out servers
	//back to the list, normal heartbeats only keep it there
	server.genHandle(LM_Heartbeat, [this](Server& srv, Transport& trans, Address addr, Message& msg) {
		if(msg.readBit()) {
			GameDesc desc;
			desc.read(msg);

			int port = desc.address.port;
			desc.address = addr;
			desc.address.port = port;

			if(desc.punchPort >= 0)
				desc.punchPort = addr.port;

			time_now(desc.lastHeartbeat);

			bool has = false;
			{
				threads::ReadLock lock(mutex);
				auto it = games.find(addr);
				has = (it != games.end());

				if(has) {
					if(logging) {
						if(desc.players != it->second.players)
							log("  [PP] Server \"%s\" on %s now has %d players.",
									desc.name.c_str(), desc.address.toString().c_str(), desc.players);
					}

					it->second = desc;
				}
			}

			if(!has) {
				threads::WriteLock lock(mutex);
				games[addr] = desc;

				if(logging)
					log("[SS] New server \"%s\" on %s. (comm port %d)",
							desc.name.c_str(), desc.address.toString().c_str(), addr.port);
			}
		}
		else {
			threads::ReadLock lock(mutex);
			auto it = games.find(addr);

			if(it != games.end()) {
				GameDesc& desc = it->second;
				time_now(desc.lastHeartbeat);
				if(desc.punchPort >= 0)
					desc.punchPort = addr.port;
			}
		}
	});

	//Respond to lobby queries from clients
	server.genHandle(LM_Query, [this](Server& srv, Transport& trans, Address addr, Message& msg) {
		//Read filters
		LobbyFilters filters;
		msg >> filters.name >> filters.mod;
		msg >> filters.full >> filters.started;

		Message* mess = 0;
		unsigned short num = 0;
		msize_t numpos = 0;
		unsigned short total = 0;

		threads::ReadLock lock(mutex);
		auto it = games.begin(), end = games.end();
		for(; it != end; ++it) {
			LobbyServer::GameDesc& desc = it->second;

			//Don't list unlisted games
			if(!desc.listed)
				continue;

			//Apply filters
			if(!filterLobby(desc, filters))
				continue;

			//Create a new message if necessary
			if(!mess) {
				mess = new Message(LM_Result);
				numpos = mess->reserve<unsigned short>();
			}

			//Send result to client
			desc.write(*mess);
			++num;
			++total;

			if(num > 128) {
				mess->fill(numpos, num);
				trans.send(*mess, addr);
				delete mess;
				mess = 0;
				num = 0;
			}
		}

		if(mess) {
			mess->fill(numpos, num);
			trans.send(*mess, addr);
			delete mess;
		}

		Message final(LM_Results_End);
		final << total;

		trans.send(final, addr);
	});

	//Second stage of punchthrough
	server.genHandle(MT_Punchthrough, [this](Server& srv, Transport& trans, Address addr, Message& msg) {
		net::Address findAddr;
		msg >> findAddr;

		{
			threads::ReadLock lock(mutex);
			auto it = games.find(findAddr);
			if(it != games.end()) {
				net::Message reply(MT_Punchthrough);
				if(it->second.punchPort != -1) {
					reply << addr;
					net::Address replyAddr = it->first;
					trans.send(reply, replyAddr);
				}
			}
		}
	});

	server.genHandle(LM_Identify, [this](Server& srv, Transport& trans, Address addr, Message& msg) {
		Message m(LM_Identify);
		m << (unsigned char)addr.type;
		if(addr.type == AT_IPv4)
			m << (unsigned)addr.adr4;
		else
			m.writeBits(addr.adr6, 16 * 8);
		{
			threads::ReadLock lock(mutex);
			auto it = games.find(addr);
			if(it != games.end()) {
				GameDesc& desc = it->second;
				if(desc.punchPort == -1)
					m << (unsigned short)0;
				else
					m << (unsigned short)desc.punchPort;
			}
			else {
				m << (unsigned short)0;
			}
		}
		trans.send(m, addr);
	});
}

void LobbyServer::listen(int port, const std::string& address) {
	server.listen(port, address);
}

void LobbyServer::runThreads(int workerThreads) {
	running.signal(1);
	threads::createThread(_serverLoop, this);
	server.runThreads(workerThreads);
}

void LobbyServer::stop() {
	running.wait(0);
	server.stop();
}

LobbyServer::~LobbyServer() {
	stop();
}


threads::threadreturn threadcall _queryThread(void* data) {
	LobbyQuery* query = (LobbyQuery*)data;

	time timer, now;
	time_now(now);
	timer = now;

	while(query->active) {
		if(query->doUpdate) {
			query->update(true);
			query->doUpdate = false;
		}
		time_now(now);
		if(time_diff(timer, now) >= NET_LOBBY_QUERY_TIMEOUT) {
			if(query->totalFromServer == (unsigned short)-1 || query->receivedFromServer < query->totalFromServer) {
				query->update(false);
			}
			else {
				query->updating = false;
			}
			timer = now;
		}
		threads::sleep(10);
	}

	query->running.signalDown();
	return 0;
}

LobbyQuery::LobbyQuery(Address addr, int BroadcastPort)
	: client(addr, false), broadcast(BroadcastPort, addr.type),
		broadcastPort(BroadcastPort), handler(nullptr), receivedFromServer(0), totalFromServer((unsigned short)-1), updating(false), active(true),
		queryServer(true), queryBroadcast(BroadcastPort != -1), doUpdate(true) {
	bind();
}

LobbyQuery::LobbyQuery(const std::string& hostname, int port, int BroadcastPort, AddressType type)
	: client(hostname, port, false, type), broadcast(BroadcastPort, type),
		broadcastPort(BroadcastPort), handler(nullptr), receivedFromServer(0), totalFromServer((unsigned short)-1), updating(false), active(true),
		queryServer(true), queryBroadcast(BroadcastPort != -1), doUpdate(true), full(LFM_Ignore), started(LFM_Ignore) {
	bind();
}

void LobbyQuery::bind() {
	client.handle(LM_Result, [this](Client& cl, Message& msg) {
		Game game;
		unsigned short num;
		msg >> num;

		receivedFromServer += num;

		for(unsigned short i = 0; i < num; ++i) {
			game.read(msg);

			auto it = handled_lobbies.find(game.address);
			if(it == handled_lobbies.end()) {
				if(handler)
					handler(game);
				handled_lobbies.insert(game.address);
			}
		}

		if(receivedFromServer >= totalFromServer)
			updating = false;
	});

	client.handle(LM_Results_End, [this](Client& cl, Message& msg) {
		msg >> totalFromServer;

		if(receivedFromServer >= totalFromServer)
			updating = false;
	});

	broadcast.handle(LM_Result, [this](BroadcastClient& cl, Address addr, Message& msg) {
		Game game;
		game.read(msg);

		int port = game.address.port;
		game.address = addr;
		game.address.port = port;
		game.punchPort = -1;
		game.isLocal = true;

		auto it = handled_lobbies.find(game.address);
		if(it == handled_lobbies.end()) {
			if(handler)
				handler(game);
			handled_lobbies.insert(game.address);
		}
	});

	client.runThreads(1);

	running.signalUp();
	threads::createThread(_queryThread, this);

	if(broadcastPort != -1)
		broadcast.runThreads(1);
}

void LobbyQuery::refresh(bool doQuery, bool doBroadcast) {
	queryServer = doQuery;
	queryBroadcast = doBroadcast;
	doUpdate = true;
	updating = true;
	totalFromServer = (unsigned short)-1;
}

void LobbyQuery::update(bool clear) {
	if(clear)
		handled_lobbies.clear();

	//Build query
	Message msg(LM_Query);
	msg << name << mod;
	msg << (uint8_t)full;
	msg << (uint8_t)started;

	//Query the lobby server
	if(queryServer) {
		client << msg;

		receivedFromServer = 0;
		totalFromServer = -1;
		updating = true;
	}

	//Query on broadcast
	if(queryBroadcast && broadcastPort != -1)
		broadcast.broadcast(msg);
}

void LobbyQuery::stop() {
	client.stop();
	updating = false;
	active = false;

	running.wait(0);

	if(broadcastPort != -1)
		broadcast.stop();
}

LobbyQuery::~LobbyQuery() {
	stop();
}
	
};
