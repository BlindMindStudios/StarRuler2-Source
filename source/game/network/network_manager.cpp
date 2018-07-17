#include "network.h"
#include "network/network_manager.h"
#include "threads.h"
#include "main/logging.h"
#include "main/initialization.h"
#include "main/references.h"
#include "obj/universe.h"
#include "obj/lock.h"
#include "empire.h"
#include "scripts/binds.h"
#include "assert.h"
#include "processing.h"
#include "util/random.h"
#include "design/design.h"
#include "design/effector.h"
#include "physics/physics_world.h"
#include "scene/particle_system.h"
#include "main/game_platform.h"
#include <math.h>
#include <unordered_set>

extern bool queuedModSwitch;
extern std::vector<std::string> modSetup;
extern std::unordered_set<std::string> dlcList;
extern void checkDLC();

const char* messageNames[MT_COUNT - MT_START] = {
	"MT_Event_Call",
	"MT_Object_Component_Call",
	"MT_Empire_Component_Call",
	"MT_Start_Game",
	"MT_End_Game",
	"MT_Game_Ready",
	"MT_Request_Galaxy",
	"MT_Object_Data",
	"MT_Create_Empire",
	"MT_Script_Sync_Initial",
	"MT_Script_Sync_Periodic",
	"MT_Galaxy_Header",
	"MT_Galaxy_Done",
	"MT_Request_Object_Details",
	"MT_Design_Data",
	"MT_Design_Update",
	"MT_Effector_Update",
	"MT_Effector_Trigger",
	"MT_Game_Speed",
	"MT_Nickname"
};

const char* DisconnectReasonText[] = {
	"timed out",
	"error",
	"closed",
	"kicked",
	"version mismatch",
	"invalid password",
	"null"
};

const std::string MS_SERVER("ms.starruler2.com");
const int MS_PORT = 8892;
const int BROADCAST_PORT = 8889;

extern void startNewGame(); // From bind_menu.cpp
int NetworkManager::MP_VERSION = 0;

struct galaxySend {
	NetworkManager* mgr;
	Player* to;
};

bool Player::controls(Empire* emp) {
	if(!emp)
		return false;
	return controlMask & emp->mask || emp == this->emp;
}

bool Player::views(Empire* emp) {
	if(!emp)
		return false;
	if(!emp->valid())
		return true;
	return viewMask & emp->mask || emp == this->emp;
}

threads::threadreturn threadcall asyncSendGalaxy(void* arg) {
	enterSection(NS_Network);
	galaxySend& data = *(galaxySend*)arg;
	initNewThread();
	data.mgr->sendGalaxy(data.to);
	cleanupThread();
	delete &data;
	return 0;
}

void writeGameTime(net::Message& msg, double time, bool highDetail = true) {
	double ipart;
	double frac = modf(time, &ipart);

	if(highDetail) {
		char secIndex = char(ipart);
		unsigned char pctSec = (unsigned char)(frac * 256.0);

		msg << secIndex << pctSec;
	}
	else {
		unsigned char secIndex = (unsigned char)ipart % 16;
		unsigned char pctSec = (unsigned char)(frac * 16.0);
		unsigned char byte = (secIndex << 4) | pctSec;
		msg << byte;
	}
}

double readGameTime(net::Message& msg, bool highDetail = true) {
	double t = floor(devices.driver->getGameTime());

	if(highDetail) {
		char secIndex;
		unsigned char pctSec;

		msg >> secIndex >> pctSec;

		//Find nearest second that can produce the index
		char curIndex = char(t);

		char diff = secIndex - curIndex;
		t += double(diff);
		t += double(pctSec) / 256.0;

		return t;
	}
	else {
		unsigned char byte = 0;
		msg >> byte;

		unsigned char curIndex = (unsigned char)t % 16;

		unsigned char secIndex = byte >> 4;
		unsigned char pctSec = byte & 0x0f;

		char diff = curIndex - secIndex;
		if(diff > 7)
			diff -= 16;
		else if(diff < 8)
			diff += 16;
		t += double(diff);
		t += (double(pctSec) + randomd()) / 16.0;

		return t;
	}
}

static bool stopSync = false;
static bool syncRunning = false;
static threads::Mutex deltaMutex, sendGalaxyMutex;
static unsigned serializationInProgress = 0;
static double resumeSpeed = 0;
static unsigned pauseCounter = 0;

struct AsyncObjectDetailRequest : public ObjectMessage {
	int plyID;

	AsyncObjectDetailRequest(Object* obj, int toID) : ObjectMessage(obj), plyID(toID) {
		obj->grab();
	}

	void process() {
		devices.network->sendObjectDetails(object, plyID);
	}

	~AsyncObjectDetailRequest() {
		object->drop();
	}
};

static threads::threadreturn threadcall syncLoop(void* data) {
	enterSection(NS_Network);
	initNewThread();
	syncRunning = true;
	stopSync = false;

	while(!stopSync) {
		int startTime = devices.driver->getTime();

		deltaMutex.lock();

		if(devices.network->hasSyncedClients && devices.network->serverReady) {
			//Randomly send a few object detail updates
			if(unsigned childCount = devices.universe->children.size()) {
				threads::ReadLock lock(devices.universe->childLock);
				for(unsigned i = 0; i < NET_DETAILED_PERTICK; ++i) {
					Object* obj = devices.universe->children[randomi(0,childCount-1)];
					if(obj->isInitialized() && !obj->getFlag(objStopTicking))
						obj->lockGroup->addMessage(new AsyncObjectDetailRequest(obj, -1));
				}
			}

			//Send any remaining deltas and time syncs
			{
				threads::ReadLock lock(devices.network->playerLock);
				net::Message tmsg(MT_Time_Sync);
				for(auto i = devices.network->players.begin(), end = devices.network->players.end(); i != end; ++i) {
					Player& player = *i->second;

					if(!player.conn || !player.conn->active || !player.hasGalaxy)
						continue;

					tmsg.reset();
					tmsg << devices.driver->getGameTime() << devices.driver->getGameSpeed() << devices.driver->getTime();
					devices.network->send(&player, tmsg);

					auto& batch = devices.network->batches[player.id];

					auto sendBatch = [&player](bool& condition, net::Message& msg, threads::Mutex& lock) {
						if(condition) {
							lock.lock();
							devices.network->send(&player, msg);
							msg.reset();
							condition = false;
							lock.release();
						}
					};
					
					sendBatch(batch->hasObjDatas, batch->objData, batch->objLock);
					sendBatch(batch->hasProjs, batch->projs, batch->projLock);
				}
			}

			//Do periodic syncs for any scripts that want them
			net::Message smsg(MT_Script_Sync_Periodic, net::MF_Managed);
			foreach(it, devices.scripts.server->modules) {
				scripts::Module& mod = *it->second;
				auto* func = mod.callbacks[scripts::SC_sync_periodic];
				if(func) {
					smsg.reset();
					smsg.write0();
					smsg << it->first;

					bool sendDelta = false;
					scripts::Call cl = devices.scripts.server->call(func);
					cl.push((void*)&smsg);
					cl.call(sendDelta);

					if(sendDelta)
						devices.network->sendAll(smsg, true);
				}
			}
		}

		deltaMutex.release();

		//Sleep until the next sync tick
		int endTime = devices.driver->getTime();
		int remaining = (startTime + NET_DELTA_INTERVAL) - endTime;
		if(remaining > 0)
			threads::sleep(remaining);
		else
			threads::sleep(1);
	}
	syncRunning = false;
	cleanupThread();
	return 0;
}

void NetworkManager::host(const std::string& gamename, int port, unsigned maxPlayers,
	bool isPublic, bool punchthrough, const std::string& password)
{
	net::prepare();
	disconnect();
	waitForClients = true;
	isClient = false;
	isServer = true;
	server = new net::Server(port);
	serverReady = false;
	hasSyncedClients = false;
	currentPlayer.id = 1;
	currentPlayer.hasGalaxy = true;
	connected = true;
	this->password = password;

	heartbeat = new net::LobbyHeartbeat(net::Address(MS_SERVER, MS_PORT), BROADCAST_PORT);
	if(punchthrough)
		heartbeat->enablePunchthrough(server);

	if(!syncRunning)
		threads::createThread(syncLoop, this);

	std::string modString;
	for(unsigned i = 0, cnt = devices.mods.activeMods.size(); i < cnt; ++i) {
		auto* mod = devices.mods.activeMods[i];
		if(mod->name == "base")
			continue;
		if(!modString.empty())
			modString += "\n";
		modString += mod->name;
	}

	heartbeat->name = gamename;
	heartbeat->players = 1;
	heartbeat->maxPlayers = maxPlayers;
	heartbeat->started = false;
	heartbeat->password = !password.empty();
	heartbeat->address.port = port;
	heartbeat->version = MP_VERSION;
	heartbeat->listed = isPublic;
	heartbeat->mod = modString;
	heartbeat->run(true);

	server->threadInit = [](bool main) {
		enterSection(NS_Network);
		initNewThread();
	};

	server->threadExit = [](bool main) {
		cleanupThread();
	};

	server->connHandle(net::MT_Connect, [this](net::Server& srv, net::Connection& conn, net::Message& mess) {
		print("Connection from %s", conn.address.toString().c_str());

		threads::WriteLock lock(playerLock);
		Player* pl = new Player(nextPlayerId++);
		pl->address = conn.address;
		pl->conn = &conn;
		pl->emp = Empire::getSpectatorEmpire();
		pl->defaultSequence = new net::Sequence(conn); //TODO: Leaks a sequence
		players[pl->id] = pl;
		batches[pl->id] = new PlayerBatches();
		connmap[&conn] = pl;

		net::Message playerMsg(MT_Player_ID, net::MF_Managed);
		playerMsg << pl->id;
		playerMsg << MP_VERSION;
		playerMsg.writeBit(!this->password.empty());

		uint64_t lobby = 0;
		if(devices.cloud)
			lobby = devices.cloud->getLobby();
		playerMsg << lobby;

		unsigned cnt = devices.mods.activeMods.size();
		if(cnt == 1 && devices.mods.activeMods[0]->name == "base") {
			playerMsg.writeSmall(0);
		}
		else {
			playerMsg.writeSmall(cnt);
			for(unsigned i = 0; i < cnt; ++i)
				playerMsg << devices.mods.activeMods[i]->name;
		}

		//Send DLC
		playerMsg.writeSmall(dlcList.size());
		for(auto it = dlcList.begin(), end = dlcList.end(); it != end; ++it)
			playerMsg << *it;

		this->send(pl, playerMsg);

		if(monitorBandwidth)
			monitorIn(mess);
	});

	server->connHandle(net::MT_Disconnect, [this](net::Server& srv, net::Connection& conn, net::Message& mess) {
		net::DisconnectReason reason;
		mess >> reason;
		if(reason > net::DR_NULL)
			reason = net::DR_NULL;

		std::string name("???");

		threads::WriteLock lock(playerLock);
		Player* pl = getPlayer(conn);
		if(pl) {
			name = std::string(pl->nickname);
			if(pl->emp) {
				pl->emp->player = 0;
				pl->emp = 0;
			}
			pl->hasGalaxy = false;
			players.erase(pl->id);
			delete batches[pl->id];
			batches.erase(pl->id);
			connmap.erase(&conn);
			//delete pl;
			//TODO: This leaks little player structs.
			//Deleting it isn't exactly safe, though, since
			//things can have requested it from this or the empire.
		}

		print("Disconnection from %s - %s (%s)",
			name.c_str(),
			conn.address.toString().c_str(),
			DisconnectReasonText[reason]);

		if(monitorBandwidth)
			monitorIn(mess);
	});

	server->connHandle(MT_Nickname, [this](net::Server& srv, net::Connection& conn, net::Message& mess) {
		threads::WriteLock lck(playerLock);
		std::string nick;
		mess >> nick;

		int version;
		mess >> version;
		if(version != MP_VERSION) {
			srv.kick(conn, net::DR_Version);
			return;
		}

		std::string pwd;
		mess >> pwd;
		if(!this->password.empty() && this->password != pwd) {
			srv.kick(conn, net::DR_Password);
			return;
		}

		Player* pl = getPlayer(conn);
		if(pl) {
			strncpy(pl->nickname, nick.c_str(), 32);
			pl->nickname[31] = '\0';
		}

		if(serverReady) {
			//Check if we have an empire to put this in
			unsigned cnt = Empire::getEmpireCount();
			for(unsigned i = 0; i < cnt; ++i) {
				Empire* other = Empire::getEmpireByIndex(i);
				if(other->player == nullptr && other->lastPlayer.ipEquals(pl->address)) {
					pl->emp = other;
					other->player = pl;
					other->lastPlayer = pl->address;
					break;
				}
			}

			//Tell the client to start the game now if
			//we're already in one
			net::Message startMsg(MT_Start_Game, net::MF_Managed);
			this->send(pl, startMsg);

			net::Message readyMsg(MT_Game_Ready, net::MF_Managed);
			this->send(pl, readyMsg);
		}

		print("%s is now known as %s", conn.address.toString().c_str(), nick.c_str());

		if(monitorBandwidth)
			monitorIn(mess);
	});

	server->connHandle(MT_Event_Call, [this](net::Server& srv, net::Connection& conn, net::Message& msg) {
		Player* pl = getPlayer(conn);
		if(pl) {
			auto* man = scripts::handleEventMessage(pl, msg, true);
			if(man != nullptr) {
				ManagerMessage mm;
				mm.manager = man;
				mm.message = new net::Message(msg);
				mm.message->rewind();
				mm.player = pl;

				threads::Lock lock(managerMtx);
				managerQueue.push_back(mm);
			}
		}
		if(monitorBandwidth)
			monitorIn(msg);
	});

	server->connHandle(MT_Object_Component_Call, [this](net::Server& srv, net::Connection& conn, net::Message& msg) {
		Player* pl = getPlayer(conn);
		if(pl)
			scripts::handleObjectComponentMessage(pl, msg);
		if(monitorBandwidth)
			monitorIn(msg);
	});

	server->connHandle(MT_Empire_Component_Call, [this](net::Server& srv, net::Connection& conn, net::Message& msg) {
		Player* pl = getPlayer(conn);
		if(pl)
			scripts::handleEmpireComponentMessage(pl, msg);
		if(monitorBandwidth)
			monitorIn(msg);
	});

	server->connHandle(MT_Request_Galaxy, [this](net::Server& srv, net::Connection& conn, net::Message& msg) {
		info("Galaxy request from %s", conn.address.toString().c_str());
		Player* pl = getPlayer(conn);
		if(pl) {
			auto* data = new galaxySend();
			data->mgr = this;
			data->to = pl;
			threads::createThread(asyncSendGalaxy, data);
		}
		if(monitorBandwidth)
			monitorIn(msg);
	});

	server->connHandle(MT_Galaxy_Done, [this](net::Server& srv, net::Connection& conn, net::Message& msg) {
		info("Player received galaxy.");
		if(monitorBandwidth)
			monitorIn(msg);

		Player* pl = getPlayer(conn);
		pl->hasGalaxy = true;
	});

	server->connHandle(MT_Request_Object_Details, [this](net::Server& srv, net::Connection& conn, net::Message& msg) {
		Player* pl = getPlayer(conn);

		Object* obj = readObject(msg, false);
		if(obj) {
			AsyncObjectDetailRequest* request = new AsyncObjectDetailRequest(obj, pl->id);
			obj->lockGroup->addMessage(request);
			obj->drop();
		}
		if(monitorBandwidth)
			monitorIn(msg);
	});

	server->connHandle(MT_Design_Data, [this](net::Server& srv, net::Connection& conn, net::Message& msg) {
		Player* pl = getPlayer(conn);
		Empire* plEmp = pl->emp;
		if(!pl || !plEmp)
			return;

		//Read the design into the appropriate empire
		std::string clsname;
		Design* dsg;
		{
			threads::WriteLock lock(plEmp->designMutex);
			msg >> clsname;

			DesignClass* cls = plEmp->getDesignClass(clsname);
			dsg = plEmp->recvDesign(msg);
			if(!dsg)
				return;
			dsg->cls = cls;
			plEmp->makeDesignIcon(dsg);
			cls->designs.push_back(dsg);
		}

		//Inform all the clients
		net::Message notify(MT_Design_Data, net::MF_Managed);
		notify << plEmp->id;
		notify << clsname;
		plEmp->sendDesign(notify, dsg, true);

		sendOther(pl, notify, true);
	});

	server->connHandle(MT_Design_Update, [this](net::Server& srv, net::Connection& conn, net::Message& msg) {
		Player* pl = getPlayer(conn);
		if(!pl || !pl->emp)
			return;

		//Read the design into the appropriate empire
		const Design* older = nullptr;
		DesignClass* cls = nullptr;
		Design* newer = nullptr;
		{
			threads::WriteLock lock(pl->emp->designMutex);
			unsigned id;
			msg >> id;
			older = pl->emp->getDesign(id);
			if(!older)
				return;

			std::string clsname;
			msg >> clsname;
			cls = pl->emp->getDesignClass(clsname, true);
			if(!cls)
				return;

			newer = pl->emp->recvDesign(msg);
			pl->emp->setDesign(older, newer, cls);
		}

		//Inform all the clients
		net::Message notify(MT_Design_Update, net::MF_Managed);
		notify << pl->emp->id;
		notify << older->id;
		notify.write1();
		notify << cls->name;
		pl->emp->sendDesign(notify, newer, true);

		sendOther(pl, notify, true);
	});

	print("Hosting on port %d", port);
	server->runThreads(4);
}

class AsyncNetworkParticles : public scene::NodeEvent {
public:
	const scene::ParticleSystemDesc* sys;
	vec3d position, velocity;
	quaterniond rot;
	float scale;
	Object* nodeObject;

	AsyncNetworkParticles(const scene::ParticleSystemDesc* System) : NodeEvent(nullptr), sys(System), nodeObject(nullptr) {
	}

	~AsyncNetworkParticles() {
		if(nodeObject)
			nodeObject->drop();
	}

	void process() override {
		scene::Node* node = nullptr;
		if(nodeObject) {
			node = nodeObject->node;
			if(!node)
				return;
		}

		scene::playParticleSystem(sys, node, position, rot, nodeObject ? velocity + nodeObject->velocity : velocity, scale);
	}
};

struct AsyncObjectDelta : public ObjectMessage {
	double time;
	net::Message msg;

	AsyncObjectDelta(Object* obj, double fromTime) : ObjectMessage(obj), time(fromTime), msg(net::MT_Invalid) {
		obj->grab();
	}

	void process() {
		object->recvDelta(msg, time);
	}

	~AsyncObjectDelta() {
		object->drop();
	}
};

struct AsyncObjectDetails : public ObjectMessage {
	double time;
	net::Message msg;

	AsyncObjectDetails(Object* obj, double fromTime) : ObjectMessage(obj), time(fromTime), msg(net::MT_Invalid) {
		obj->grab();
	}

	void process() {
		object->recvDetailed(msg, time);
	}

	~AsyncObjectDetails() {
		object->drop();
	}
};

struct AsyncObjectDetailsSight : public ObjectMessage {
	double time;
	net::Message msg;
	vec3d pos, vel, accel;
	quaterniond rot;

	AsyncObjectDetailsSight(Object* obj, double fromTime) : ObjectMessage(obj), time(fromTime), msg(net::MT_Invalid) {
		obj->grab();
	}

	void process() {
		double tDiff = time - object->lastTick;
		object->position = pos + (vel + (accel * (tDiff * 0.5))) * tDiff;
		object->velocity = vel + accel * tDiff;
		object->acceleration = accel;
		object->rotation = rot;

		object->recvDetailed(msg, time);
	}

	~AsyncObjectDetailsSight() {
		object->drop();
	}
};

NetworkManager::NetworkManager()
	: currentPlayer(1), nextPlayerId(2), isServer(false), isClient(false),
		server(0), client(0), defaultSequence(0),
		heartbeat(nullptr), punch(nullptr), query(nullptr),
		serverReady(false), clientReady(false),
		hasGalaxy(false), hasSyncedClients(false),
		connected(false), monitorBandwidth(false),
		lastMonitorTick(0), menuTimer(0.0),
		galaxyProgress(0.f), empireProgress(0.f),
		objectProgress(0.f), galaxiesInFlight(0)
{
	players[currentPlayer.id] = &currentPlayer;

	totalSeconds = 0;
	for(unsigned i = 0; i < MT_COUNT - MT_START; ++i) {
		totalIncomingData[i] = 0;
		totalOutgoingData[i] = 0;
		totalIncomingPackets[i] = 0;
		totalOutgoingPackets[i] = 0;
	}
}

void NetworkManager::setPassword(const std::string& pwd) {
	threads::WriteLock lck(playerLock);
	password = pwd;
	if(heartbeat)
		heartbeat->password = !pwd.empty();
}

void NetworkManager::connect(const std::string& hostname, int port, const std::string& password, bool tryPunchthrough) {
	net::prepare();
	net::Address addr(hostname, port);
	connect(addr, password);
	if(tryPunchthrough)
		punch = new net::LobbyPunchthrough(net::Address(MS_SERVER, MS_PORT), client);
	net::clear();
}

void NetworkManager::connect(const net::Address& addr, bool tryPunchthrough, bool attemptOnly, const std::string& password) {
	net::prepare();
	connect(addr, password, attemptOnly);
	if(tryPunchthrough)
		punch = new net::LobbyPunchthrough(net::Address(MS_SERVER, MS_PORT), client);
	net::clear();
}

void NetworkManager::connect(net::Game& game, bool disablePunchthrough, const std::string& password) {
	if(!disablePunchthrough && game.punchPort != -1) {
		net::Address connAddr(game.address);
		connAddr.port = game.punchPort;
		connect(connAddr, password);

		punch = new net::LobbyPunchthrough(net::Address(MS_SERVER, MS_PORT), client);
	}
	else {
		connect(game.address, password);
	}
}

void NetworkManager::connect(const net::Address& addr, const std::string& password, bool attemptOnly) {
	net::prepare();
	disconnect();
	resetNetState();
	client = new net::Client(addr);
	defaultSequence = new net::Sequence(*client);
	connected = false;
	serverReady = false;
	clientReady = false;
	hasSyncedClients = false;
	currentPlayer.id = 1;
	currentPlayer.hasGalaxy = false;
	this->password = password;

	if(!attemptOnly)
		prepNetState();

	client->threadInit = [](bool main) {
		enterSection(NS_Network);
		initNewThread();
	};

	client->threadExit = [](bool main) {
		cleanupThread();
	};

	client->handle(net::MT_Connect, [this](net::Client& cl, net::Message& msg) {
		print("Connection established to %s", cl.address.toString().c_str());

		if(monitorBandwidth)
			monitorIn(msg);
	});

	client->handle(net::MT_Disconnect, [this](net::Client& cl, net::Message& msg) {
		if(devices.cloud)
			devices.cloud->announceDisconnect();

		net::DisconnectReason reason;
		msg >> reason;

		this->disconnection = reason;
		print("Disconnection from %s (%d)", cl.address.toString().c_str(), reason);

		if(monitorBandwidth)
			monitorIn(msg);
	});

	client->handle(MT_Player_ID, [this](net::Client& cl, net::Message& msg) {
		int id;
		msg >> id;
		currentPlayer.id = id;

		int version;
		msg >> version;
		msg.readBit();

		uint64_t lobby = 0;
		msg >> lobby;
		if(devices.cloud && lobby != 0 && (!devices.cloud->inQueue() && devices.cloud->getLobby() == 0))
			devices.cloud->joinLobby(lobby);

		unsigned modCnt = msg.readSmall();
		int myVersion = MP_VERSION;
		modSetup.clear();
		std::vector<bool> activeChecks(devices.mods.activeMods.size(), false);
		bool needChange = false;
		for(unsigned i = 0; i < modCnt; ++i) {
			std::string mod;
			msg >> mod;
			if(devices.mods.getMod(mod) == nullptr) {
				myVersion = -1;
				break;
			}
			if(!needChange) {
				bool found = false;
				for(unsigned n = 0; n < activeChecks.size(); ++n) {
					if(devices.mods.activeMods[n]->name == mod) {
						activeChecks[n] = true;
						found = true;
						break;
					}
				}
				if(!found)
					needChange = true;
			}
			modSetup.push_back(mod);
		}
		if(!needChange) {
			for(unsigned n = 0; n < activeChecks.size(); ++n) {
				if(devices.mods.activeMods[n]->name == "base")
					continue;
				if(!activeChecks[n]) {
					needChange = true;
					break;
				}
			}
		}
		if(myVersion != -1 && needChange) {
			if(modSetup.empty())
				modSetup.push_back("base");
			queuedModSwitch = true;
		}
		else
			modSetup.clear();

		//Read DLC
		unsigned dlcCount = msg.readSmall();
		dlcList.clear();
		for(unsigned i = 0; i < dlcCount; ++i) {
			std::string dlc;
			msg >> dlc;
			dlcList.insert(dlc);
		}

		net::Message nickMsg(MT_Nickname, net::MF_Managed);
		nickMsg << std::string(currentPlayer.nickname);
		nickMsg << myVersion;
		nickMsg << this->password;
		this->send(nickMsg);

		connected = true;
		if(monitorBandwidth)
			monitorIn(msg);
	});

	client->handle(MT_Event_Call, [this](net::Client& cl, net::Message& msg) {
		auto* man = scripts::handleEventMessage(&currentPlayer, msg, true);
		if(man != nullptr) {
			ManagerMessage mm;
			mm.manager = man;
			mm.message = new net::Message(msg);
			mm.message->rewind();
			mm.player = &currentPlayer;

			threads::Lock lock(managerMtx);
			managerQueue.push_back(mm);
		}
		if(monitorBandwidth)
			monitorIn(msg);
	});

	client->handle(MT_Start_Game, [this](net::Client& cl, net::Message& msg) {
		info("Server indicated to start the game.");
		startNewGame();
		if(monitorBandwidth)
			monitorIn(msg);
	});

	client->handle(MT_Game_Ready, [this](net::Client& cl, net::Message& msg) {
		info("Server indicated game is ready.");
		serverReady = true;
		if(monitorBandwidth)
			monitorIn(msg);
	});

	client->handle(MT_Game_Speed, [this](net::Client& cl, net::Message& msg) {
		double speed = 1.0;
		msg >> speed;
		devices.driver->setGameSpeed(speed);

		if(monitorBandwidth)
			monitorIn(msg);
	});

	client->handle(MT_Object_Data, [this](net::Client& cl, net::Message& msg) {
		if(monitorBandwidth)
			monitorIn(msg);

		//Check that we can read at least a char
		// Technically the header is ~3 bits, but all of these currently use at least a char in addition
		while(msg.canRead<char>()) {
			unsigned eventType = msg.readLimited(OE_MAX);
			if(msg.hasError())
				break;
			switch(eventType) {
			case OE_Create: {
				double fromTime = readGameTime(msg);
				unsigned size = msg.readSmall();
				msg.readAlign();

				net::Message tmp(net::MT_Invalid);
				msg.copyTo(tmp, msg.getReadPosition().bytes, msg.getReadPosition().bytes + size);
				recvObjectInitial(tmp, fromTime);

				msg.advance(size * 8);
				galaxyProgress += objectProgress;
			} break;
			case OE_Destroy: {
				Object* obj = readObject(msg, false);
				if(obj) {
					obj->flagDestroy();
					obj->drop();
				}
				else {
					error("Attempted to destroy an unknown object.");
				}
			} break;
			case OE_Hide: {
				Object* obj = readObject(msg, false);
				if(obj) {
					//Need to hide this object from view
					obj->visibleMask = 0;
					obj->drop();
				}
				else {
					error("Attempted to hide an unknown object.");
				}
			} break;
			case OE_VisionDetails: {
				double t = readGameTime(msg);
				if(msg.hasError())
					break;
				Object* obj = readObject(msg, false);

				if(obj && !obj->getFlag(objUninitialized)) {
					ObjectLock lock(obj);
					AsyncObjectDetailsSight* ad = new AsyncObjectDetailsSight(obj, t);

					msg.readMedVec3(ad->pos.x, ad->pos.y, ad->pos.z);
					msg.readSmallVec3(ad->vel.x, ad->vel.y, ad->vel.z);
					msg.readSmallVec3(ad->accel.x, ad->accel.y, ad->accel.z);
					msg.readRotation(ad->rot.xyz.x, ad->rot.xyz.y, ad->rot.xyz.z, ad->rot.w);
					unsigned size = msg.readSmall();

					msg.readAlign();
					auto pos = msg.getReadPosition();
					if(!msg.hasError()) {
						msg.copyTo(ad->msg, pos.bytes, pos.bytes + size);
						msg.advance(size * 8);

						if(!msg.hasError()) {
							obj->lockGroup->addMessage(ad);
							ad = nullptr;
						}
					}

					if(ad)
						delete ad;
				}
				else {
					//Read in and skip sight info about unknown object
					error("Received vision information about an unknown object.");
					quaterniond q;
					msg.readMedVec3(q.xyz.x, q.xyz.y, q.xyz.z);
					msg.readSmallVec3(q.xyz.x, q.xyz.y, q.xyz.z);
					msg.readSmallVec3(q.xyz.x, q.xyz.y, q.xyz.z);
					msg.readRotation(q.xyz.x, q.xyz.y, q.xyz.z, q.w);
					unsigned size = msg.readSmall();
					msg.readAlign();
					msg.advance(size*8);
				}

				if(obj)
					obj->drop();
			} break;
			case OE_Delta: {
				double t = readGameTime(msg);
				Object* obj = readObject(msg, false);
				if(obj && !obj->getFlag(objUninitialized)) {
					bool visibleBit = msg.readBit();

					//Receiving a delta means the object is visible to us
					if(obj->getFlag(objMemorable)) {
						if(visibleBit) {
							obj->visibleMask |= Empire::getPlayerEmpire()->mask;
							obj->sightedMask |= obj->visibleMask;
						}
						else {
							auto empMask = Empire::getPlayerEmpire()->mask;
							obj->visibleMask &= ~empMask;
							obj->sightedMask |= empMask;
						}
					}
					else {
						obj->visibleMask |= Empire::getPlayerEmpire()->mask;
						obj->sightedMask |= obj->visibleMask;
					}

					//Receive actual data
					unsigned size = msg.readSmall();
					msg.readAlign();
					auto pos = msg.getReadPosition();
					if(!msg.hasError()) {
						AsyncObjectDelta* asyncDelta = new AsyncObjectDelta(obj, t);
						msg.copyTo(asyncDelta->msg, pos.bytes, pos.bytes + size);
						msg.advance(size * 8);

						if(!msg.hasError())
							obj->lockGroup->addMessage(asyncDelta);
						else
							delete asyncDelta;
					}
					else {
						return;
					}
				}
				else {
					if(!obj)
						error("Received delta about unknown object.");
					else
						error("Received delta about uninitialized object (%d).", obj->id);

					(void)msg.readBit();
					unsigned size = msg.readSmall();
					msg.readAlign();
					msg.advance(size * 8);
				}

				if(obj)
					obj->drop();
			} break;
			case OE_Detailed: {
				double t = readGameTime(msg);
				Object* obj = readObject(msg, false);
				if(obj && !obj->getFlag(objUninitialized)) {
					unsigned size = msg.readSmall();
					msg.readAlign();
					auto pos = msg.getReadPosition();
					if(!msg.hasError()) {
						AsyncObjectDetails* asyncDetails = new AsyncObjectDetails(obj, t);
						msg.copyTo(asyncDetails->msg, pos.bytes, pos.bytes + size);
						msg.advance(size * 8);

						if(!msg.hasError())
							obj->lockGroup->addMessage(asyncDetails);
						else
							delete asyncDetails;
					}
				}
				else {
					error("Received detailed message about unknown object.");
					unsigned size = msg.readSmall();
					msg.readAlign();
					msg.advance(size * 8);
				}

				if(obj)
					obj->drop();
			} break;
			default:
				error("Received invalid object data message");
				return;
			}
		}
	});

	client->handle(MT_Create_Empire, [this](net::Client& cl, net::Message& msg) {
		Empire* emp = recvEmpireInitial(msg);
		if(msg.readBit()) {
			Empire::setPlayerEmpire(emp);
			currentPlayer.emp = emp;
			emp->player = &currentPlayer;
		}
		galaxyProgress += empireProgress;
		if(monitorBandwidth)
			monitorIn(msg);
	});

	client->handle(MT_Script_Sync_Initial, [this](net::Client& cl, net::Message& msg) {
		std::string modname;
		msg >> modname;

		scripts::Module* mod = devices.scripts.server->getModule(modname.c_str());
		if(mod) {
			info("Receiving script '%s'.", modname.c_str());
			auto* func = mod->callbacks[scripts::SC_sync_initial];
			if(func) {
				scripts::Call cl = devices.scripts.server->call(func);
				cl.push((void*)&msg);
				cl.call();
			}
		}
		if(monitorBandwidth)
			monitorIn(msg);
	});

	client->handle(MT_Script_Sync_Periodic, [this](net::Client& cl, net::Message& msg) {
		auto* manager = devices.scripts.server;
		if(msg.readBit()) {
			manager = devices.scripts.menu;

			ManagerMessage mm;
			mm.manager = manager;
			mm.message = new net::Message(msg);

			threads::Lock lock(managerMtx);
			managerQueue.push_back(mm);

			return;
		}

		std::string modname;
		msg >> modname;

		scripts::Module* mod = manager->getModule(modname.c_str());
		if(mod) {
			auto* func = mod->callbacks[scripts::SC_recv_periodic];
			if(func) {
				scripts::Call cl = manager->call(func);
				cl.push((void*)&msg);
				cl.call();
			}
		}
		if(monitorBandwidth)
			monitorIn(msg);
	});

	client->handle(MT_Galaxy_Header, [this](net::Client& cl, net::Message& msg) {
		double time, speed;
		int srvTime;
		msg >> time >> speed >> srvTime;
		devices.driver->resetGameTime(time);
		devices.driver->setGameSpeed(speed);
		serverTimeOffset = srvTime - devices.driver->getTime();
		readGameConfig(msg);

		unsigned empCnt, objCnt;
		msg >> empCnt;
		msg >> objCnt;

		galaxyProgress = 0.f;
		empireProgress = 0.5f * (1.f / float(empCnt));
		objectProgress = 0.5f * (1.f / float(objCnt));

		if(msg.readBit())
			devices.physics = PhysicsWorld::fromMessage(msg);
		if(msg.readBit())
			devices.nodePhysics = PhysicsWorld::fromMessage(msg);
		if(monitorBandwidth)
			monitorIn(msg);
	});

	client->handle(MT_Galaxy_Done, [this](net::Client& cl, net::Message& msg) {
		info("Receiving galaxy done, starting scripts.");
		currentPlayer.hasGalaxy = true;
		if(monitorBandwidth)
			monitorIn(msg);

		galaxyProgress = 1.f;
		net::Message done(MT_Galaxy_Done, net::MF_Reliable);
		send(done);
	});

	client->handle(MT_Design_Data, [this](net::Client& srv, net::Message& msg) {
		if(monitorBandwidth)
			monitorIn(msg);

		//Get empire to put the design in
		unsigned char empID;
		msg >> empID;
		Empire* emp = Empire::getEmpireByID(empID);
		if(!emp)
			return;

		//Read the design
		std::string clsname;
		msg >> clsname;

		threads::WriteLock lock(emp->designMutex);

		DesignClass* cls = emp->getDesignClass(clsname);
		Design* dsg = emp->recvDesign(msg, true);
		if(!dsg)
			return;
		dsg->cls = cls;
		emp->makeDesignIcon(dsg);
		cls->designs.push_back(dsg);
	});

	client->handle(MT_Design_Update, [this](net::Client& srv, net::Message& msg) {
		if(monitorBandwidth)
			monitorIn(msg);

		//Get empire to put the design in
		unsigned char empID;
		msg >> empID;
		Empire* emp = Empire::getEmpireByID(empID);
		if(!emp)
			return;

		//Read the design
		threads::WriteLock lock(emp->designMutex);

		unsigned olderID;
		msg >> olderID;
		const Design* older = emp->getDesign(olderID);

		DesignClass* cls = nullptr;
		if(msg.readBit()) {
			std::string clsname;
			msg >> clsname;
			cls = emp->getDesignClass(clsname, true);
		}

		Design* newer = emp->recvDesign(msg, true);
		if(!newer || !older)
			return;

		if(cls)
			emp->setDesign(older, newer, cls);
		else
			emp->setDesignUpdate(older, newer);
	});

	client->handle(MT_Effector_Update, [this](net::Client& srv, net::Message& msg) {
		if(monitorBandwidth)
			monitorIn(msg);
		auto* eff = Effector::receiveUpdate(msg);
		if(eff)
			eff->drop();
	});

	client->handle(MT_Effector_Trigger, [this](net::Client& srv, net::Message& msg) {
		if(monitorBandwidth)
			monitorIn(msg);

		while(msg.canRead<char>()) {
			heldPointer<const Effector> eff;
			if(msg.readBit()) {
				unsigned char emp;
				msg >> emp;

				unsigned dsg = msg.readSmall();

				Empire* empire = Empire::getEmpireByID(emp);
				if(!empire)
					return;
			
				//NOTE: If we don't know about the design, we can't get through the message safely
				const Design* design = empire->getDesign(dsg);
				if(!design)
					return;

				const Subsystem& sys = design->subsystems[msg.readLimited(design->subsystems.size())];
				eff = &sys.effectors[msg.readLimited(sys.type->effectors.size())];
			}
			else {
				unsigned id = msg.readSmall();
				eff = getEffector(id);
				if(!eff)
					return;
			}

			double t = readGameTime(msg, false);

			heldPointer<Object> obj, target;
			obj.set(readObject(msg, false));
			int type = -1;
			if(msg.readBit()) {
				if(obj)
					type = obj->type->id;
				else
					type = 0;
			}
			target.set(readObject(msg, false, type));
			if(!obj || !target) {
				if(eff->tracking > 0) {
					vec3d dir;
					if(msg.readBit())
						msg.readDirection(dir.x, dir.y, dir.z, 8);
				}
			}
			else {
				EffectorTarget targ;
				targ.target = target;
				targ.hits = 0;
				targ.flags = 0;
				if(eff->tracking > 0) {
					if(msg.readBit())
						msg.readDirection(targ.tracking.x, targ.tracking.y, targ.tracking.z, 8);
					else
						targ.tracking = (target->position - obj->position).normalized();
					targ.flags |= TF_TrackingProgress;
					targ.tracking = obj->rotation.inverted() * targ.tracking;
				}
				else
					targ.tracking = (target->position - obj->position).normalized();

				if(!obj->getFlag(objUninitialized) && !target->getFlag(objUninitialized))
					eff->type.triggerGraphics(obj, targ, eff, nullptr, nullptr, 1.f, std::min(t - devices.driver->getGameTime(), 0.0));
			}
		}
	});

	client->handle(MT_Particle_System, [this](net::Client& srv, net::Message& msg) {
		std::string pSys;
		msg >> pSys;
		auto* system = devices.library.getParticleSystem(pSys);
		if(!system)
			return;

		auto* effect = new AsyncNetworkParticles(system);
		
		if(msg.readBit()) {
			effect->nodeObject = readObject(msg, false);
			msg.readSmallVec3(effect->position.x, effect->position.y, effect->position.z);
		}
		else {
			msg.readMedVec3(effect->position.x, effect->position.y, effect->position.z);
		}
		msg.readSmallVec3(effect->velocity.x, effect->velocity.y, effect->velocity.z);
		msg.readRotation(effect->rot.xyz.x, effect->rot.xyz.y, effect->rot.xyz.z, effect->rot.w);
		msg >> effect->scale;

		if(msg.hasError()) {
			delete effect;
			return;
		}

		scene::queueNodeEvent(effect);
	});

	client->handle(MT_Time_Sync, [this](net::Client& srv, net::Message& msg) {
		double srvGameTime, srvGameSpeed;
		int srvTime;

		msg >> srvGameTime >> srvGameSpeed >> srvTime;
		if(msg.hasError())
			return;

		double goalTime = srvGameTime + double(srvTime - devices.driver->getTime() - serverTimeOffset) / 1000.0 * srvGameSpeed;
		double time = devices.driver->getGameTime();

		double tDiff = goalTime - time;
		double speed = std::max(0.0, srvGameSpeed + tDiff / 10.0);

		devices.driver->setGameSpeed(speed);
		setGameSpeed(speed);
	});

	print("Connecting to %s", addr.toString().c_str());
	client->runThreads(4);
}

void NetworkManager::queryServers() {
	if(query == nullptr) {
		//Prepare the network for Windows, the lobby query will keep the network alive
		net::prepare();
		query = new net::LobbyQuery(MS_SERVER, MS_PORT, BROADCAST_PORT);
		query->handler = [this](net::Game& game) {
			threads::Lock lock(queryMtx);
			queryResult.push_back(game);
		};
		net::clear();
	}
	{
		threads::Lock lock(queryMtx);
		queryResult.clear();
	}
	query->refresh();
}

void NetworkManager::disconnect() {
	if(punch) {
		punch->stop();
		delete punch;
		punch = nullptr;
	}
	if(server) {
		connected = false;
		server->stop();
		stopSync = true;
		while(server->active || syncRunning)
			threads::sleep(1);
		delete server;
		server = nullptr;
		net::clear();
	}
	if(client) {
		connected = false;
		client->stop();
		while(client->active)
			threads::sleep(1);
		delete client;
		client = nullptr;
		hasGalaxy = false;
		net::clear();
	}
	if(heartbeat) {
		heartbeat->stop();
		while(heartbeat->active)
			threads::sleep(1);
		delete heartbeat;
		heartbeat = nullptr;
	}
	{
		threads::Lock lock(managerMtx);
		foreach(it, managerQueue)
			delete it->message;
		managerQueue.clear();
		menuTimer = 0.0;
	}
	password = "";
	if(devices.cloud)
		devices.cloud->announceDisconnect();

	//Remove all players, and add back the local player
	{
		threads::WriteLock lock(playerLock);
		players.clear();
		connmap.clear();
		for(auto i = batches.begin(), end = batches.end(); i != end; ++i)
			delete i->second;
		batches.clear();
		players[currentPlayer.id] = &currentPlayer;
	}

	//Recheck all the DLC
	checkDLC();
}

void NetworkManager::managerNetworking(scripts::Manager* manager, double time) {
	//Run any messages for this manager
	if(!managerQueue.empty()) {
		threads::Lock lock(managerMtx);
		for(auto it = managerQueue.begin(); it != managerQueue.end(); ) {
			if(it->manager == manager) {
				net::Message& msg = *it->message;

				if(msg.getType() == MT_Script_Sync_Periodic) {
					std::string modname;
					msg >> modname;

					scripts::Module* mod = manager->getModule(modname.c_str());
					if(mod) {
						auto* func = mod->callbacks[scripts::SC_recv_periodic];
						if(func) {
							scripts::Call cl = manager->call(func);
							cl.push((void*)&msg);
							cl.call();
						}
					}
				}
				else if(msg.getType() == MT_Event_Call) {
					scripts::handleEventMessage(it->player, msg, false);
				}

				delete it->message;
				it = managerQueue.erase(it);
			}
			else {
				++it;
			}
		}
	}

	//Do menu sync if we have any players at all
	if(server && players.size() > 1 && manager == devices.scripts.menu) {
		menuTimer += time;
		if(menuTimer > 0.25) {
			threads::Lock lock(deltaMutex);
			net::Message smsg(MT_Script_Sync_Periodic, net::MF_Managed);
			foreach(it, manager->modules) {
				scripts::Module& mod = *it->second;
				auto* func = mod.callbacks[scripts::SC_sync_periodic];
				if(func) {
					smsg.reset();
					smsg.write1();
					smsg << it->first;

					bool sendDelta = false;
					scripts::Call cl = manager->call(func);
					cl.push((void*)&smsg);
					cl.call(sendDelta);

					if(sendDelta)
						sendAll(smsg);
				}
			}
			menuTimer = 0.0;
		}
	}
}

void NetworkManager::tick(double time) {
	if(client) {
		if(serverReady && clientReady && !hasGalaxy) {
			requestGalaxy();
			hasGalaxy = true;
		}
		if(!client->active) {
			disconnect();
			return;
		}
	}
	if(server) {
		if(heartbeat)
			heartbeat->players = players.size();
		if(!server->active) {
			disconnect();
			return;
		}
		else if(devices.cloud && heartbeat->identified && heartbeat->externalIP) {
			unsigned port = heartbeat->address.port;
			if(heartbeat->externalPort > 0)
				port = heartbeat->externalPort;
			devices.cloud->announceServer(heartbeat->externalIP, (unsigned short)port, password);
		}
	}

	if(monitorBandwidth) {
		double time = devices.driver->getAccurateTime();
		if(time - lastMonitorTick >= 1.0) {
			currentOutgoing = 0;
			currentIncoming = 0;
			queuedPackets = 0;

			for(auto i = connmap.begin(), end = connmap.end(); i != end; ++i) {
				unsigned inBW = 0, outBW = 0, packs = 0;
				i->first->getTraffic(inBW, outBW, packs);
				currentOutgoing += outBW;
				currentIncoming += inBW;
				queuedPackets = packs;
			}

			for(unsigned i = 0; i < MT_COUNT - MT_START; ++i) {

				lastIncomingData[i] = incomingData[i];
				incomingData[i] = 0;

				lastIncomingPackets[i] = incomingPackets[i];
				incomingPackets[i] = 0;

				lastOutgoingData[i] = outgoingData[i];
				outgoingData[i] = 0;

				lastOutgoingPackets[i] = outgoingPackets[i];
				outgoingPackets[i] = 0;

				totalIncomingData[i] += lastIncomingData[i];
				totalIncomingPackets[i] += lastIncomingPackets[i];
				totalOutgoingData[i] += lastOutgoingData[i];
				totalOutgoingPackets[i] += lastOutgoingPackets[i];
				totalSeconds += 1;

				//currentOutgoing += lastOutgoingData[i];
				//currentIncoming += lastIncomingData[i];
			}

			lastMonitorTick = time;
		}
	}
}

void NetworkManager::monitorIn(net::Message& msg, unsigned count) {
	auto type = msg.getType();
	if(type < MT_START || type >= MT_COUNT)
		return;
	incomingData[type - MT_START] += msg.size() * count;
	incomingPackets[type - MT_START] += count;
}

void NetworkManager::monitorOut(net::Message& msg, unsigned count) {
	auto type = msg.getType();
	if(type < MT_START || type >= MT_COUNT)
		return;
	outgoingData[type - MT_START] += msg.size() * count;
	outgoingPackets[type - MT_START] += count;
}

void NetworkManager::dumpIncomingMonitor() {
	print("Incoming network bandwidth:");
	for(unsigned i = 0; i < MT_COUNT - MT_START; ++i) {
		if(lastIncomingPackets[i] == 0)
			continue;
		print("  %s: %s/s in %d packets (~%s per)",
			messageNames[i],
			toSize(lastIncomingData[i]).c_str(),
			lastIncomingPackets[i],
			toSize(lastIncomingData[i] / lastIncomingPackets[i]).c_str());
	}
}

void NetworkManager::dumpOutgoingMonitor() {
	print("Outgoing network bandwidth:");
	for(unsigned i = 0; i < MT_COUNT - MT_START; ++i) {
		if(lastOutgoingPackets[i] == 0)
			continue;
		print("  %s: %s/s in %d packets (~%s per)",
			messageNames[i],
			toSize(lastOutgoingData[i]).c_str(),
			lastOutgoingPackets[i],
			toSize(lastOutgoingData[i] / lastOutgoingPackets[i]).c_str());
	}
}

void NetworkManager::dumpIncomingTotals() {
	print("Incoming network bandwidth totals:");
	for(unsigned i = 0; i < MT_COUNT - MT_START; ++i) {
		if(totalIncomingPackets[i] == 0)
			continue;
		print("  %s: %s in %d packets (~%s/packet, ~%s/s)",
			messageNames[i],
			toSize(totalIncomingData[i]).c_str(),
			totalIncomingPackets[i],
			toSize(totalIncomingData[i] / totalIncomingPackets[i]).c_str(),
			toSize(totalIncomingData[i] / totalSeconds).c_str());
	}
}

void NetworkManager::dumpOutgoingTotals() {
	print("Outgoing network bandwidth totals:");
	for(unsigned i = 0; i < MT_COUNT - MT_START; ++i) {
		if(totalOutgoingPackets[i] == 0)
			continue;
		print("  %s: %s in %d packets (~%s/packet, ~%s/s)",
			messageNames[i],
			toSize(totalOutgoingData[i]).c_str(),
			totalOutgoingPackets[i],
			toSize(totalOutgoingData[i] / totalOutgoingPackets[i]).c_str(),
			toSize(totalOutgoingData[i] / totalSeconds).c_str());
	}
}

void NetworkManager::kick(int playerId) {
	if(!server)
		return;
	threads::WriteLock lock(playerLock);
	Player* pl = getPlayer(playerId);
	if(pl == nullptr) {
		print("could not find player %d to kick", playerId);
		return;
	}
	if(!pl->conn)
		return;
	server->kick(*pl->conn);
}

Player* NetworkManager::getPlayer(int id) {
	threads::ReadLock lock(playerLock);
	if(id == currentPlayer.id)
		return &currentPlayer;
	auto it = players.find(id);
	if(it != players.end())
		return it->second;
	return 0;
}

Player* NetworkManager::getPlayer(net::Connection& conn) {
	threads::ReadLock lock(playerLock);
	auto it = connmap.find(&conn);
	if(it != connmap.end())
		return it->second;
	return 0;
}

void NetworkManager::send(net::Message& msg) {
	assert(client);
	if(msg.getFlag(net::MF_Sequenced))
		*defaultSequence << msg;
	else
		*client << msg;
	if(monitorBandwidth)
		monitorOut(msg);
}

void NetworkManager::send(Player* sendTo, net::Message& msg) {
	assert(server);
	assert(sendTo->conn);
	if(msg.getFlag(net::MF_Sequenced))
		*sendTo->defaultSequence << msg;
	else
		*sendTo->conn << msg;
	if(monitorBandwidth)
		monitorOut(msg);
}

void NetworkManager::sendAll(net::Message& msg, bool requireGalaxy) {
	assert(server);
	if(requireGalaxy || msg.getFlag(net::MF_Sequenced)) {
		threads::ReadLock lock(playerLock);
		foreach(it, players) {
			Player& pl = *it->second;
			if(!pl.conn)
				continue;
			if(requireGalaxy && !pl.wantsDeltas)
				continue;
			if(msg.getFlag(net::MF_Sequenced))
				*pl.defaultSequence << msg;
			else
				*pl.conn << msg;
			if(monitorBandwidth)
				monitorOut(msg);
		}
	}
	else {
		server->sendAll(msg);
		if(monitorBandwidth)
			monitorOut(msg, (unsigned)players.size() - 1);
	}
}

void NetworkManager::sendEmpire(net::Message& msg, Empire* emp) {
	assert(server);
	threads::ReadLock lock(playerLock);
	foreach(it, players) {
		Player& pl = *it->second;
		if(!pl.conn)
			continue;
		if(!pl.wantsDeltas)
			continue;
		if(!pl.emp || pl.emp != emp)
			continue;
		if(msg.getFlag(net::MF_Sequenced))
			*pl.defaultSequence << msg;
		else
			*pl.conn << msg;
		if(monitorBandwidth)
			monitorOut(msg);
	}
}

void NetworkManager::sendMasked(net::Message& msg, unsigned mask) {
	assert(server);
	threads::ReadLock lock(playerLock);
	foreach(it, players) {
		Player& pl = *it->second;
		if(!pl.conn)
			continue;
		if(!pl.wantsDeltas)
			continue;
		//Only filter out players with an empire chosen (spectators still get the message, should be done differently?)
		if(pl.emp && (pl.emp->mask & mask) == 0)
			continue;
		if(msg.getFlag(net::MF_Sequenced))
			*pl.defaultSequence << msg;
		else
			*pl.conn << msg;
		if(monitorBandwidth)
			monitorOut(msg);
	}
}

void NetworkManager::sendVisionMasked(net::Message& msg, unsigned mask) {
	assert(server);
	threads::ReadLock lock(playerLock);
	foreach(it, players) {
		Player& pl = *it->second;
		if(!pl.conn)
			continue;
		if(!pl.wantsDeltas)
			continue;
		//Only filter out players with an empire chosen (spectators still get the message, should be done differently?)
		if(pl.emp && (pl.emp->visionMask & mask) == 0)
			continue;
		if(msg.getFlag(net::MF_Sequenced))
			*pl.defaultSequence << msg;
		else
			*pl.conn << msg;
		if(monitorBandwidth)
			monitorOut(msg);
	}
}

void NetworkManager::sendOther(Player* notTo, net::Message& msg, bool requireGalaxy) {
	assert(server);
	threads::ReadLock lock(playerLock);
	foreach(it, players) {
		Player& pl = *it->second;
		if(!pl.conn)
			continue;
		if(pl.id == notTo->id)
			continue;
		if(requireGalaxy && !pl.wantsDeltas)
			continue;
		if(msg.getFlag(net::MF_Sequenced))
			*pl.defaultSequence << msg;
		else
			*pl.conn << msg;
		if(monitorBandwidth)
			monitorOut(msg);
	}
}

void NetworkManager::requestGalaxy() {
	assert(client);
	net::Message msg(MT_Request_Galaxy, net::MF_Managed);
	send(msg);
}

void NetworkManager::startSignal() {
	assert(server);
	net::Message msg(MT_Start_Game, net::MF_Managed);
	sendAll(msg);
	if(players.size() == 1)
		waitForClients = false;
}

void NetworkManager::signalServerReady() {
	assert(server);

	isServer = true;
	serverReady = true;
	if(heartbeat) {
		if(devices.cloud && heartbeat->identified && heartbeat->externalIP) {
			unsigned port = heartbeat->address.port;
			if(heartbeat->externalPort > 0)
				port = heartbeat->externalPort;
			devices.cloud->announceServer(heartbeat->externalIP, (unsigned short)port, password);
		}
		heartbeat->started = true;
	}

	foreach(it, players) {
		if(!it->second->emp)
			it->second->emp = Empire::getSpectatorEmpire();
	}

	net::Message msg(MT_Game_Ready, net::MF_Managed);
	sendAll(msg);
}

void NetworkManager::sendParticleSystem(const std::string& id, const vec3d& position, const vec3d& velocity, const quaterniond& rot, float scale, unsigned visionMask) {
	net::Message msg(MT_Particle_System);
	msg << id;
	msg.writeBit(false);
	msg.writeMedVec3(position.x, position.y, position.z);
	msg.writeSmallVec3(velocity.x, velocity.y, velocity.z);
	msg.writeRotation(rot.xyz.x, rot.xyz.y, rot.xyz.z, rot.w);
	msg << scale;
	sendVisionMasked(msg, visionMask);
}

void NetworkManager::sendParticleSystem(const std::string& id, const vec3d& position, const vec3d& velocity, const quaterniond& rot, float scale, Object* parent) {
	net::Message msg(MT_Particle_System);
	msg << id;
	msg.writeBit(true);
	writeObject(msg, parent);
	msg.writeSmallVec3(position.x, position.y, position.z);
	msg.writeSmallVec3(velocity.x, velocity.y, velocity.z);
	msg.writeRotation(rot.xyz.x, rot.xyz.y, rot.xyz.z, rot.w);
	msg << scale;
	sendVisionMasked(msg, parent->visibleMask);
}

void NetworkManager::setNickname(const std::string& nick) {
	threads::ReadLock lock(devices.network->playerLock);
	strncpy(currentPlayer.nickname, nick.c_str(), 32);
	currentPlayer.nickname[31] = '\0';
}

void NetworkManager::signalClientReady() {
	assert(client);
	clientReady = true;
}

void syncInitial(NetworkManager* manager, Player* player, bool stageOne) {
	foreach(it, devices.scripts.server->priority_sync) {
		if(stageOne) {
			if(it->first >= 0)
				continue;
		}
		else {
			if(it->first < 0)
				continue;
		}

		scripts::Module& mod = *it->second;
		auto* func = mod.callbacks[scripts::SC_sync_initial];
		if(func) {
			net::Message msg(MT_Script_Sync_Initial, net::MF_Managed);
			msg << mod.name;

			scripts::Call cl = devices.scripts.server->call(func);
			cl.push((void*)&msg);
			cl.call();

			info("Sending script '%s' (%d).", mod.name.c_str(), it->first);

			manager->send(player, msg);
		}
	}
}

void NetworkManager::sendGalaxy(Player* player) {
	assert(server);

	info("Sending galaxy....\n");

	bool pauseUntilReceived = waitForClients;

	//Pause the game state while sending it
	sendGalaxyMutex.lock();
	if(galaxiesInFlight == 0) {
		if(++pauseCounter == 1) {
			resumeSpeed = devices.driver->getGameSpeed();
			devices.driver->setGameSpeed(0);
			setGameSpeed(0.0);
		}
	}
	if(serializationInProgress == 0) {
		processing::pause();
		devices.universe->doQueued();
		deltaMutex.lock();
	}
	galaxiesInFlight += 1;
	serializationInProgress += 1;
	sendGalaxyMutex.release();

	unsigned empCnt = Empire::getEmpireCount();

	net::Message header(MT_Galaxy_Header, net::MF_Managed);
	header << devices.driver->getGameTime();
	header << devices.driver->getGameSpeed();
	header << devices.driver->getTime();
	writeGameConfig(header);
	header << (unsigned)empCnt;
	header << (unsigned)devices.universe->children.size();
	if(devices.physics) {
		header.write1();
		devices.physics->writeSetup(header);
	}
	else {
		header.write0();
	}
	if(devices.nodePhysics) {
		header.write1();
		devices.nodePhysics->writeSetup(header);
	}
	else {
		header.write0();
	}
	send(player, header);

	net::msize_t bytes = 0;

	//Send empires
	for(unsigned i = 0; i < empCnt; ++i) {
		Empire* emp = Empire::getEmpireByIndex(i);

		net::Message msg(MT_Create_Empire, net::MF_Managed);
		emp->sendInitial(msg);

		info("Sending empire '%s' (%d).",
			emp->name.c_str(), emp->id);

		msg.writeBit(emp->player == player);

		bytes += msg.size();
		send(player, msg);
	}

	info("Empire Data: %d bytes", bytes);
	bytes = 0;

	//Send effectors
	foreach(it, effectorMap) {
		auto& eff = *it->second;
		net::Message msg(MT_Effector_Update, net::MF_Managed);
		eff.sendUpdate(msg);
		bytes += msg.size();
		send(player, msg);
	}

	info("Effector Data: %d bytes", bytes);
	bytes = 0;

	struct ObjBytes {
		unsigned count;
		net::msize_t bytes;
		ObjBytes() : count(0), bytes(0) {}
		void record(net::msize_t Bytes) { bytes += Bytes; ++count; }
	} objBytes[256];

	//Send high priority script modules
	syncInitial(this, player, true);

	//Send each object
	info("Sending objects.");
	{
		bool unsent = false;
		net::Message msg(MT_Object_Data, net::MF_Managed);
		net::Message tmp(net::MT_Invalid);
		auto p = tmp.getReadPosition().bytes;
		foreach(it, devices.universe->children) {
			Object& obj = **it;
			msg.writeLimited(OE_Create, OE_MAX);
			writeGameTime(msg, obj.lastTick);
			obj.sendInitial(tmp);
			msg.writeSmall(tmp.size()-p);
			msg.writeAlign();
			tmp.copyTo(msg,p);
			tmp.reset();
			msg.writeAlign();

			if(auto* type = obj.type) {
				objBytes[type->id].record(msg.size());
				bytes += msg.size();
			}

			if(msg.size() > NET_DELTA_PACKETHINT) {
				send(player, msg);
				msg.reset();
				unsent = false;
			}
			else {
				unsent = true;
			}
		}

		if(unsent)
			send(player, msg);
	}

	info("Object Data: %d bytes", bytes);
	for(unsigned i = 0; i < 256; ++i) {
		if(objBytes[i].count == 0)
			continue;

		auto* type = getScriptObjectType(i);
		info(" %s: %d bytes, %.1f per", type->name.c_str(), objBytes[i].bytes, (double)objBytes[i].bytes / (double)objBytes[i].count);
	}
	bytes = 0;

	//Send low priority script modules
	syncInitial(this, player, false);

	//Send final message
	net::Message msg(MT_Galaxy_Done, net::MF_Managed);
	send(player, msg);

	info("Finished sending galaxy....\n");

	player->wantsDeltas = true;

	sendGalaxyMutex.lock();
	serializationInProgress -= 1;
	if(serializationInProgress == 0) {
		deltaMutex.release();
		processing::resume();
	}
	
	if(!pauseUntilReceived) {
		if(--pauseCounter == 0) {
			devices.driver->setGameSpeed(resumeSpeed);
			setGameSpeed(resumeSpeed);
		}
	}
	sendGalaxyMutex.release();

	hasSyncedClients = true;
	while(!player->hasGalaxy && player->conn->active)
		threads::idle();

	//Resume locked states
	sendGalaxyMutex.lock();
	galaxiesInFlight -= 1;
	if(pauseUntilReceived) {
		if(--pauseCounter == 0) {
			devices.driver->setGameSpeed(resumeSpeed);
			setGameSpeed(resumeSpeed);
		}
	}
	if(galaxiesInFlight == 0)
		waitForClients = false;
	sendGalaxyMutex.release();
}

void NetworkManager::sendObject(Object* obj) {
	assert(server);
	if(!hasSyncedClients)
		return;

	net::Message tmp(net::MT_Invalid);
	auto p = tmp.getReadPosition().bytes;
	obj->sendInitial(tmp);

	threads::ReadLock lock(playerLock);
	for(auto i = players.begin(), end = players.end(); i != end; ++i) {
		auto& ply = *i->second;
		if(!ply.conn || !ply.conn->active || !ply.wantsDeltas)
			continue;

		auto& batch = batches[ply.id];
		threads::Lock lock(batch->objLock);
		auto& msg = batch->objData;

		msg.writeLimited(OE_Create, OE_MAX);
		writeGameTime(msg, obj->lastTick);
		msg.writeSmall(tmp.size()-p);
		msg.writeAlign();
		tmp.copyTo(msg,p);
		msg.writeAlign();

		if(msg.size() >= NET_DELTA_PACKETHINT) {
			send(&ply, msg);
			msg.reset();
			batch->hasObjDatas = false;
		}
		else {
			batch->hasObjDatas = true;
		}
	}
}

void NetworkManager::sendObjectDelta(Object* obj) {
	assert(server);
	if(!hasSyncedClients)
		return;

	net::Message delta(net::MT_Invalid);
	auto p = delta.getReadPosition().bytes;
	if(!obj->sendDelta(delta))
		return;

	threads::ReadLock lock(playerLock);
	for(auto i = players.begin(), end = players.end(); i != end; ++i) {
		auto& ply = *i->second;
		if(!ply.conn || !ply.conn->active || !ply.wantsDeltas)
			continue;
		if(ply.emp && !obj->isVisibleTo(ply.emp) && !(obj->getFlag(objMemorable) && obj->isKnownTo(ply.emp)))
			continue;

		auto& batch = batches[ply.id];
		threads::Lock lock(batch->objLock);
		auto& msg = batch->objData;
		msg.writeLimited(OE_Delta, OE_MAX);
		writeGameTime(msg, obj->lastTick);
		writeObject(msg, obj);
		//Vision info for memorable objects
		msg.writeBit(!ply.emp || obj->isVisibleTo(ply.emp));
		msg.writeSmall(delta.size()-p);
		msg.writeAlign();
		delta.copyTo(msg, p);
		msg.writeAlign();

		if(msg.size() >= NET_DELTA_PACKETHINT) {
			send(&ply, msg);
			msg.reset();
			batch->hasObjDatas = false;
		}
		else {
			batch->hasObjDatas = true;
		}
	}
}

void NetworkManager::sendObjectDetails(Object* obj, int toPlayerID) {
	assert(server);
	if(!hasSyncedClients)
		return;
		
	net::Message details(net::MT_Invalid);
	auto p = details.getReadPosition().bytes;
	obj->sendDetailed(details);

	threads::ReadLock lock(playerLock);
	for(auto i = players.begin(), end = players.end(); i != end; ++i) {
		auto& ply = *i->second;
		if(!ply.conn || !ply.conn->active || !ply.wantsDeltas || (toPlayerID != -1 && ply.id != toPlayerID))
			continue;
		if(ply.emp && !obj->isVisibleTo(ply.emp) && !(obj->getFlag(objMemorable) && obj->isKnownTo(ply.emp)))
			continue;

		auto& batch = batches[ply.id];
		threads::Lock lock(batch->objLock);
		auto& msg = batch->objData;
		msg.writeLimited(OE_Detailed, OE_MAX);
		writeGameTime(msg, obj->lastTick);
		writeObject(msg, obj);
		msg.writeSmall(details.size()-p);
		msg.writeAlign();
		details.copyTo(msg, p);
		msg.writeAlign();

		if(msg.size() >= NET_DELTA_PACKETHINT) {
			send(&ply, msg);
			msg.reset();
			batch->hasObjDatas = false;
		}
		else {
			batch->hasObjDatas = true;
		}

		break;
	}
}

void NetworkManager::sendObjectVisionDelta(Object* obj, unsigned prevMask, unsigned newMask) {
	assert(server);
	if(!hasSyncedClients)
		return;

	bool gotDetails = false;
	net::Message details(net::MT_Invalid);
	auto p = details.getReadPosition().bytes;
	auto getDetails = [&]() {
		if(!gotDetails) {
			obj->sendDetailed(details);
			gotDetails = true;
		}
	};

	threads::ReadLock lock(playerLock);
	for(auto i = players.begin(), end = players.end(); i != end; ++i) {
		auto& ply = *i->second;
		if(!ply.conn || !ply.conn->active || !ply.wantsDeltas)
			continue;
		auto& batch = batches[ply.id];
		//We check by mask rather than vision mask; the callers are responsible for checking visionMask
		unsigned mask = ply.emp ? ply.emp->mask : 0;
		if(mask != 0 && (mask & newMask) == 0 && (mask & prevMask) != 0) {
			threads::Lock lock(batch->objLock);
			auto& msg = batch->objData;
			msg.writeLimited(OE_Hide, OE_MAX);
			writeObject(msg, obj);
			if(msg.size() >= NET_DELTA_PACKETHINT) {
				send(&ply, msg);
				msg.reset();
				batch->hasObjDatas = false;
			}
			else {
				batch->hasObjDatas = true;
			}
		}
		else if(mask == 0 || ((mask & newMask) != 0 && (mask & prevMask) == 0) ) {
			threads::Lock lock(batch->objLock);
			auto& msg = batch->objData;
			msg.writeLimited(OE_VisionDetails, OE_MAX);
			writeGameTime(msg, obj->lastTick);
			writeObject(msg, obj);

			msg.writeMedVec3(obj->position.x, obj->position.y, obj->position.z);
			msg.writeSmallVec3(obj->velocity.x, obj->velocity.y, obj->velocity.z);
			msg.writeSmallVec3(obj->acceleration.x, obj->acceleration.y, obj->acceleration.z);
			msg.writeRotation(obj->rotation.xyz.x, obj->rotation.xyz.y, obj->rotation.xyz.z, obj->rotation.w);
			
			getDetails();
			msg.writeSmall(details.size()-p);
			msg.writeAlign();
			details.copyTo(msg, p);
			msg.writeAlign();

			if(msg.size() >= NET_DELTA_PACKETHINT) {
				send(&ply, msg);
				msg.reset();
				batch->hasObjDatas = false;
			}
			else {
				batch->hasObjDatas = true;
			}
		}
	}
}

void NetworkManager::requestDetailed(Object* obj) {
	assert(client);
	net::Message msg(MT_Request_Object_Details, net::MF_Reliable);
	writeObject(msg, obj);
	send(msg);
}

void NetworkManager::destroyObject(Object* obj) {
	if(!hasSyncedClients || !server)
		return;

	threads::ReadLock lock(playerLock);
	for(auto i = players.begin(), end = players.end(); i != end; ++i) {
		auto& ply = *i->second;
		if(!ply.conn || !ply.conn->active || !ply.wantsDeltas)
			continue;

		auto& batch = batches[ply.id];
		threads::Lock lock(batch->objLock);
		auto& msg = batch->objData;

		msg.writeLimited(OE_Destroy, OE_MAX);
		writeObject(msg, obj);

		if(msg.size() >= NET_DELTA_PACKETHINT) {
			send(&ply, msg);
			msg.reset();
			batch->hasObjDatas = false;
		}
		else {
			batch->hasObjDatas = true;
		}
	}
}

void NetworkManager::sendDesign(Empire* emp, DesignClass* cls, const Design* dsg) {
	if(server) {
		if(!hasSyncedClients)
			return;
		net::Message msg(MT_Design_Data, net::MF_Managed);
		msg << emp->id;
		msg << cls->name;
		emp->sendDesign(msg, dsg, true);
		sendAll(msg, true);
	}
	else if(client) {
		net::Message msg(MT_Design_Data, net::MF_Managed);
		msg << cls->name;
		emp->sendDesign(msg, dsg);
		send(msg);
	}
}

void NetworkManager::sendDesignUpdate(Empire* emp, const Design* older, const Design* newer, DesignClass* cls) {
	if(server) {
		if(!hasSyncedClients)
			return;
		net::Message msg(MT_Design_Update, net::MF_Managed);
		msg << emp->id;
		msg << older->id;
		if(cls) {
			msg.write1();
			msg << cls->name;
		}
		else {
			msg.write0();
		}
		emp->sendDesign(msg, newer, true);
		sendAll(msg, true);
	}
	else if(client) {
		net::Message msg(MT_Design_Update, net::MF_Managed);
		msg << older->id;
		msg << cls->name;
		emp->sendDesign(msg, newer);

		send(msg);
	}
}

void NetworkManager::sendEffectorUpdate(const Effector* eff) {
	if(!hasSyncedClients)
		return;
	net::Message msg(MT_Effector_Update, net::MF_Managed);
	eff->sendUpdate(msg);
	sendAll(msg, true);
}

void NetworkManager::sendEffectorDestruction(const Effector* eff) {
	if(!hasSyncedClients)
		return;
	net::Message msg(MT_Effector_Update, net::MF_Managed);
	eff->sendDestruction(msg);
	sendAll(msg, true);
}

void NetworkManager::sendEffectorTrigger(const EffectorDef* eff, const Effector* efftr, Object* obj, const EffectorTarget& target, double atTime) {
	if(!hasSyncedClients)
		return;
	//TODO: Send large, rarely fired weapons as reliable
	net::Message msg(net::MT_Invalid);
	auto p = msg.getReadPosition().bytes;

	if(efftr->effectorId == 0) {
		msg.write1();
		const Design* dsg = efftr->inDesign;
		msg << dsg->owner->id;
		msg.writeSmall(dsg->id);
		msg.writeLimited(efftr->subsysIndex, dsg->subsystems.size());
		msg.writeLimited(efftr->effectorIndex, dsg->subsystems[efftr->subsysIndex].type->effectors.size());
	}
	else {
		msg.write0();
		msg.writeSmall(efftr->effectorId);
	}

	writeGameTime(msg, atTime, false);
	writeObject(msg, obj, true);
	auto* targ = target.target;
	msg.writeBit(targ->type == obj->type);
	writeObject(msg, targ, targ->type != obj->type);

	if(efftr->tracking > 0) {
		vec3d globalDir = obj->rotation * target.tracking;
		bool straightAt = (targ->position - obj->position).normalize().dot(globalDir) > 0.99992470183; //Less than the error present in the direction
		msg.writeBit(!straightAt);
		if(!straightAt)
			msg.writeDirection(globalDir.x, globalDir.y, globalDir.z, 8);
	}

	unsigned sendMask = obj->visibleMask | targ->visibleMask;

	threads::ReadLock lock(playerLock);
	for(auto i = players.begin(), end = players.end(); i != end; ++i) {
		auto& ply = *i->second;
		//NOTE: Normally we only require that a player requests the galaxy to send events, but bullets are ephemeral and high-bandwidth
		if(!ply.conn || !ply.conn->active || !ply.hasGalaxy || (ply.emp && ((ply.emp->visionMask & sendMask) == 0)))
			continue;
		auto& batch = batches[ply.id];

		threads::Lock lock(batch->projLock);
		auto& out = batch->projs;
		msg.copyTo(out, p);

		if(out.size() >= NET_DELTA_PACKETHINT) {
			send(&ply, out);
			out.reset();
			batch->hasProjs = false;
		}
		else {
			batch->hasProjs = true;
		}
	}
}

bool NetworkManager::isSerializing() {
	return serializationInProgress;
}

void NetworkManager::setGameSpeed(double speed) {
	if(!hasSyncedClients)
		return;
	net::Message msg(MT_Game_Speed, net::MF_Managed);
	msg << speed;
	sendAll(msg, true);
}

void NetworkManager::endGame() {
	if(hasSyncedClients) {
		net::Message msg(MT_End_Game, net::MF_Reliable);
		sendAll(msg);
	}
	hasSyncedClients = false;
	if(syncRunning) {
		stopSync = true;
		while(syncRunning)
			threads::sleep(1);
	}
}
