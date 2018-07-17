#pragma once
#include "network/player.h"
#include "network/lobby.h"
#include "network/message_types.h"
#include "threads.h"
#include "vec3.h"
#include "quaternion.h"
#include <vector>
#include <unordered_map>

#ifndef NET_DELTA_INTERVAL
//Periodic delta flushing, etc every N ms
#define NET_DELTA_INTERVAL 125
#endif

#ifndef NET_DELTA_PACKETHINT
//If a delta packet is larger than this,
//cut it off.
#define NET_DELTA_PACKETHINT 1400
#endif

#ifndef NET_VISION_HIDE_SIZE
//Max size for a group of vision updates
#define NET_VISION_HIDE_SIZE 400
#endif

#ifndef NET_DETAILED_PERTICK
//Average amount of random detailed updates per delta tick
#define NET_DETAILED_PERTICK 16
#endif

//Message types
enum NetworkMessageType {
	MT_Event_Call = net::MT_Application,
	MT_Object_Component_Call,
	MT_Empire_Component_Call,
	MT_Start_Game,
	MT_End_Game,
	MT_Game_Ready,
	MT_Request_Galaxy,
	MT_Object_Data,
	MT_Create_Empire,
	MT_Script_Sync_Initial,
	MT_Script_Sync_Periodic,
	MT_Galaxy_Header,
	MT_Galaxy_Done,
	MT_Request_Object_Details,
	MT_Design_Data,
	MT_Design_Update,
	MT_Effector_Update,
	MT_Effector_Trigger,
	MT_Game_Speed,
	MT_Nickname,
	MT_Particle_System,
	MT_Player_ID,
	MT_Time_Sync,

	MT_COUNT,
	MT_START = net::MT_Application,
};

enum ObjectNetEvent {
	OE_Create,
	OE_Destroy,
	OE_Hide,
	OE_VisionDetails,
	OE_Delta,
	OE_Detailed,

	OE_COUNT,
	OE_MAX = OE_COUNT-1
};

namespace net {
	struct Message;
	class Client;
	class Server;
	class Connection;
	struct Address;
	struct Sequence;
};

namespace scripts {
	class Manager;
};

class Object;
class Design;
struct DesignClass;
class Effector;
class EffectorDef;
struct EffectorTarget;

struct PlayerBatches {
	threads::Mutex objLock, projLock;
	net::Message objData, projs;
	bool hasObjDatas, hasProjs;

	PlayerBatches() :
		hasObjDatas(false), hasProjs(false),
		objData(MT_Object_Data, net::MF_Managed), projs(MT_Effector_Trigger)
	{}
};

//Stub class to prepare things for network interaction
class NetworkManager {
public:
	static int MP_VERSION;
	threads::ReadWriteMutex playerLock;
	Player currentPlayer;
	std::unordered_map<int, Player*> players;
	std::unordered_map<int, PlayerBatches*> batches;
	std::unordered_map<net::Connection*, Player*> connmap;
	int nextPlayerId;

	bool isClient, isServer;
	net::Server* server;
	net::Client* client;
	net::Sequence* defaultSequence;
	net::LobbyHeartbeat* heartbeat;
	net::LobbyPunchthrough* punch;
	bool serverReady, clientReady;
	bool hasGalaxy, hasSyncedClients;
	bool connected;
	unsigned galaxiesInFlight;
	bool waitForClients;
	float galaxyProgress;
	float empireProgress;
	float objectProgress;
	std::string password;
	net::DisconnectReason disconnection;

	net::LobbyQuery* query;
	threads::Mutex queryMtx;
	std::vector<net::Game> queryResult;

	bool monitorBandwidth;
	double lastMonitorTick;
	threads::atomic_int incomingData[MT_COUNT - MT_START];
	threads::atomic_int outgoingData[MT_COUNT - MT_START];
	threads::atomic_int incomingPackets[MT_COUNT - MT_START];
	threads::atomic_int outgoingPackets[MT_COUNT - MT_START];
	int lastIncomingData[MT_COUNT - MT_START];
	int lastOutgoingData[MT_COUNT - MT_START];
	int lastIncomingPackets[MT_COUNT - MT_START];
	int lastOutgoingPackets[MT_COUNT - MT_START];
	int totalIncomingData[MT_COUNT - MT_START];
	int totalOutgoingData[MT_COUNT - MT_START];
	int totalIncomingPackets[MT_COUNT - MT_START];
	int totalOutgoingPackets[MT_COUNT - MT_START];
	int totalSeconds;
	int currentOutgoing;
	int currentIncoming;
	int queuedPackets;

	//Millisecond difference between local time and server time
	int serverTimeOffset;

	NetworkManager();

	void resetNetState() {
		isClient = false;
		isServer = false;
	}

	void prepNetState() {
		isClient = (client != nullptr);
		isServer = (server != nullptr);
	}

	//Server management
	void host(const std::string& gamename, int port, unsigned maxPlayers = 0, bool isPublic = true, bool punchthrough = true, const std::string& password = "");
	void connect(const std::string& hostname, int port, const std::string& password = "", bool tryPunchthrough = false);
	void connect(const net::Address& addr, bool tryPunchthrough, bool attemptOnly, const std::string& password);
	void connect(const net::Address& addr, const std::string& password = "", bool attemptOnly = false);
	void connect(net::Game& game, bool disablePunchthrough = false, const std::string& password = "");
	void disconnect();
	void tick(double time);
	void queryServers();
	void kick(int playerId);
	void setPassword(const std::string& pwd);

	//Bandwidth monitoring
	void monitorIn(net::Message& msg, unsigned count = 1);
	void monitorOut(net::Message& msg, unsigned count = 1);

	void dumpIncomingMonitor();
	void dumpOutgoingMonitor();

	void dumpIncomingTotals();
	void dumpOutgoingTotals();

	//Player management
	Player* getPlayer(int id);
	Player* getPlayer(net::Connection& conn);

	Player& getCurrentPlayer() {
		return currentPlayer;
	}

	//Transmit from the client to the server
	void send(net::Message& msg);

	//Transmit to clients from the server
	void send(Player* sendTo, net::Message& msg);
	void sendAll(net::Message& msg, bool requireGalaxy = false);
	void sendOther(Player* notTo, net::Message& msg, bool requireGalaxy = false);
	void sendEmpire(net::Message& msg, Empire* emp);
	void sendMasked(net::Message& msg, unsigned mask);
	void sendVisionMasked(net::Message& msg, unsigned mask);

	//Messages to script managers
	struct ManagerMessage {
		scripts::Manager* manager;
		net::Message* message;
		Player* player;
	};
	threads::Mutex managerMtx;
	std::vector<ManagerMessage> managerQueue;
	double menuTimer;
	void managerNetworking(scripts::Manager* manager, double time);

	//Specialized commands
	void setNickname(const std::string& nick);
	void signalClientReady();
	void requestGalaxy();
	void requestDetailed(Object* obj);
	void sendDesign(Empire* emp, DesignClass* cls, const Design* dsg);
	void sendDesignUpdate(Empire* emp, const Design* older, const Design* newer, DesignClass* cls = nullptr);
	void sendEffectorUpdate(const Effector* eff);
	void sendEffectorDestruction(const Effector* eff);
	void sendEffectorTrigger(const EffectorDef* eff, const Effector* efftr, Object* obj, const EffectorTarget& target, double atTime);
	void sendParticleSystem(const std::string& id, const vec3d& position, const vec3d& velocity, const quaterniond& rot, float scale, unsigned visionMask);
	void sendParticleSystem(const std::string& id, const vec3d& position, const vec3d& velocity, const quaterniond& rot, float scale, Object* parent);
	void setGameSpeed(double speed);
	bool isSerializing();

	void startSignal();
	void signalServerReady();
	void sendGalaxy(Player* player);
	void endGame();

	void sendObject(Object* obj);
	void destroyObject(Object* obj);
	void sendObjectVisionDelta(Object* obj, unsigned prevMask, unsigned newMask);
	void sendObjectDelta(Object* obj);
	void sendObjectDetails(Object* obj, int playerID = -1);
};
