#pragma once
#include "threads.h"
#include "general_states.h"
#include "design/subsystem.h"
#include "network/address.h"
#include "color.h"
#include <deque>
#include <stdint.h>
#include <unordered_map>

//Represents the controlling force behind any number of units
//Also stores global resources for controlled objects
//
//Notes:
// Creating an empire automatically registers it to the global list
class Design;
struct DesignClass;
class Shipset;
typedef uint32_t EmpMask;
typedef std::unordered_map<std::string, const Design*> designMap;
typedef std::unordered_map<std::string, DesignClass*> designClassMap;
typedef designMap::iterator designIterator;
typedef designClassMap::iterator designClassIterator;

extern unsigned validEmpireCount;
extern EmpMask currentVision[32];

namespace render {
	struct RenderState;
};

namespace net {
	struct Message;
};

class Empire;

struct EmpireMessage {
	virtual ~EmpireMessage() {}

	virtual void process(Empire* emp) {
	}
};

struct Player;
struct StatEntry;
class StatHistory;

class Object;

const unsigned char INVALID_EMPIRE = 0xff;
const unsigned char DEFAULT_EMPIRE = 0xfe;
const unsigned char SPECTATOR_EMPIRE = 0xfd;
const unsigned char UNLISTED_EMPIRE = 0xfc;

class Empire {
public:
	struct SubsystemData {
		bool unlocked;
		std::vector<bool> modulesUnlocked;
		std::unordered_map<unsigned, SubsystemDef::AppliedStage> stages;
		unsigned nextStageId;
		bool delta;

		SubsystemData() : unlocked(false), nextStageId(0), delta(false) {
		}

		void write(net::Message& msg);
		void read(const SubsystemDef* def, net::Message& msg);
	};

	std::vector<Object*> objects;
	std::vector<SubsystemData> subsysData;

	threads::Mutex msgLock, processLock;
	std::deque<EmpireMessage*> messages;
	void processMessages(unsigned maxMessages = 0xffffffff);
	void queueMessage(EmpireMessage* msg);

	unsigned char id;
	int index;
	unsigned validEmpIndex;
	std::string name;

	//Bit-mask that represents ownership of an object
	threads::Mutex maskMutex;
	EmpMask mask, visionMask, hostileMask;

	//Color used to represent this empire
	Color color;

	const render::RenderState *background, *portrait, *flag;
	std::string backgroundDef, portraitDef, flagDef;
	unsigned flagID;
	net::Address lastPlayer;
	Player* player;

	//Stats
	std::vector<StatHistory*> statHistories;
	std::vector<threads::ReadWriteMutex> statLocks;
	void recordStat(unsigned id, int value);
	void recordStatDelta(unsigned id, int delta);
	void recordStat(unsigned id, float value);
	void recordStatDelta(unsigned id, float delta);
	void recordEvent(unsigned id, unsigned short type, const std::string& name);

	const StatHistory* lockStatHistory(unsigned id);
	void unlockStatHistory(unsigned id);

	std::vector<render::SpriteSheet*> hullIcons;
	std::vector<render::SpriteSheet*> hullDistantIcons;
	std::vector<render::SpriteSheet*> hullFleetIcons;
	std::vector<Image*> hullImages;
	unsigned hullIconIndex;

	//Designs used by this empire
	heldPointer<const Shipset> shipset;
	std::string effectorSkin;

	threads::ReadWriteMutex designMutex;
	threads::ReadWriteMutex subsystemDataMutex;
	std::vector<const Design*> designIds;
	designMap designs;

	std::vector<DesignClass*> designClassIds;
	designClassMap designClasses;

	threads::ReadWriteMutex objectLock;
	void registerObject(Object* obj);
	void unregisterObject(Object* obj);
	unsigned objectCount();
	Object* findObject(unsigned i);

	Empire(unsigned char id = INVALID_EMPIRE);
	~Empire();

	bool valid();

	void cacheVision();

	//Add a design to the empire's list, cannot
	//accept duplicate names
	bool addDesign(DesignClass* cls, const Design* design);
	bool changeDesign(const Design* older, const Design* newer, DesignClass* cls = nullptr);
	void setDesign(const Design* older, const Design* newer, DesignClass* cls = nullptr);
	const Design* updateDesign(const Design* design, bool onlyOutdated);
	void setDesignUpdate(const Design* older, const Design* newer);
	void flagDesignOld(const Design* design);
	void makeDesignIcon(const Design* design);

	//Get the design by name
	DesignClass* getDesignClass(int id);
	DesignClass* getDesignClass(const std::string& name, bool add = true);
	const Design* getDesign(const std::string& name, bool grab = false);
	const Design* getDesign(unsigned id, bool grab = false);
	Design* getDesignMake(unsigned id);

	SubsystemData* getSubsystemData(const SubsystemDef* def);

	//Saving and loading
	Empire(SaveFile& file);
	void save(SaveFile& file);

	static void saveEmpires(SaveFile& file);
	static void loadEmpires(SaveFile& file);

	//Network syncing
	void sendInitial(net::Message& msg);
	void readDelta(net::Message& msg);
	void writeDelta(net::Message& msg);

	void sendDesign(net::Message& msg, const Design* dsg, bool fromServer = false);
	Design* recvDesign(net::Message& msg, bool fromServer = false);

	//Global management
	static Empire* getDefaultEmpire();
	static Empire* getSpectatorEmpire();
	static Empire* getPlayerEmpire();
	static Empire* getEmpireByIndex(unsigned index);
	static Empire* getEmpireByID(unsigned char id);

	static unsigned getEmpireCount();

	static void setPlayerEmpire(Empire* emp);
	static void initEmpires();
	static void clearEmpires();
	static void setEmpireStates(const StateDefinition* def);
	static const StateDefinition* getEmpireStates();
	
	void* operator new(size_t size);
};

Empire* recvEmpireInitial(net::Message& msg);
