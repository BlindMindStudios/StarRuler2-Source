#include "binds.h"
#include "empire.h"
#include "obj/object.h"
#include "main/references.h"
#include "main/logging.h"
#include "main/initialization.h"
#include "scripts/manager.h"
#include "scripts/generic_call.h"
#include "network/player.h"
#include "network/network_manager.h"
#include "processing.h"
#include "network.h"
#include "../as_addons/include/scriptarray.h"
#include "threads.h"
#include <string>
#include <tuple>

namespace scripts {

struct EventDesc {
	int id;
	GenericCallDesc sendToServer;
	GenericCallDesc sendToClient;

	bool onlyPrimitive;
	bool recvLocal;
	bool recvServer;
	bool recvShadow;
	bool recvMenu;
	bool passPlayer;
	std::string recvEngine;
	std::string recvModule;

	GenericCallDesc recvCall;
	Manager* recvManager;
	asIScriptFunction* recvFunc;
};

threads::Mutex eventDescMutex;
std::vector<EventDesc*> evtDescs;

void ClearEvents() {
	threads::Lock lock(eventDescMutex);
	foreach(it, evtDescs)
		delete *it;
	evtDescs.clear();
}

void ReadEvents(const std::string& filename) {
	threads::Lock lock(eventDescMutex);

	DataReader datafile(filename);
	while(datafile++) {
		std::string& line = datafile.line;

		//Split the line into the call and handler part
		std::vector<std::string> parts;
		split(line, parts, "->", true);

		if(parts.size() != 2) {
			error(datafile.position() + " - ERROR: Invalid event format.");
			continue;
		}

		std::string& call = parts[0];
		std::string& handler = parts[1];

		//Make the call descriptors
		GenericCallDesc sendToServer(call);
		bool local = false;

		//Split the handler identifier
		if(handler.compare(0, 6, "local ") == 0) {
			local = true;
			handler = handler.substr(6);
		}

		//Non-local RPCs cannot have return values
		if(!local && sendToServer.returnType.type) {
			error(datafile.position() + " - ERROR: Non-local events cannot have return values.");
			continue;
		}
		else if(sendToServer.returnType == GT_Custom_Handle) {
			error(datafile.position() + " - ERROR: Return type cannot be a custom class.");
			continue;
		}

		std::vector<std::string> scopes;
		split(handler, scopes, "::", true);

		bool recvServer = false;
		bool recvShadow = false;
		bool recvMenu = false;
		bool primitive = true;

		if(scopes[0] == "server") {
			recvServer = true;
			recvShadow = false;
		}
		else if(scopes[0] == "shadow") {
			recvServer = false;
			recvShadow = true;
		}
		else if(scopes[0] == "menu_client") {
			recvServer = false;
			recvMenu = true;
		}
		else if(scopes[0] == "menu_server") {
			recvServer = true;
			recvMenu = true;
		}

		if(local && !recvServer && !recvShadow) {
			error(datafile.position() + " - ERROR: Send-to-client events cannot be marked as local.");
			continue;
		}

		GenericCallDesc recvCall;

		GenericCallDesc sendToClient;
		sendToClient.name = sendToServer.name;
		sendToClient.argCount = 1;
		sendToClient.arguments[0] = GT_Player_Ref;

		recvCall.returnType = sendToServer.returnType;
		recvCall.returnsArray = sendToServer.returnsArray;

		for(unsigned i = 0; i < sendToServer.argCount; ++i) {
			auto& arg = sendToServer.arguments[i];
			recvCall.arguments[recvCall.argCount++] = arg;

			if(arg.type == GT_Custom_Handle) {
				arg.customName = "Serializable";
				primitive = false;
			}

			sendToClient.arguments[sendToClient.argCount++] = arg;
		}

		if(scopes.size() != 3) {
			error((datafile.position() + " - ERROR: Invalid event handler format '%s'.").c_str(), handler.c_str());
			continue;
		}

		recvCall.name = scopes[2];

		EventDesc* desc = new EventDesc();
		desc->id = (int)evtDescs.size();
		desc->recvServer = recvServer;
		desc->recvShadow = recvShadow;
		desc->recvMenu = recvMenu;
		desc->sendToServer = sendToServer;
		desc->sendToClient = sendToClient;
		desc->recvLocal = local;
		desc->recvEngine = scopes[0];
		desc->recvModule = scopes[1];
		desc->recvCall = recvCall;
		desc->recvFunc = 0;
		desc->passPlayer = false;
		desc->onlyPrimitive = primitive;

		if(desc->sendToServer.returnsArray) {
			desc->sendToServer.returnType.type = GT_Custom_Handle;
			desc->sendToServer.returnType.customName = "DataList";
		}

		if(desc->sendToClient.returnsArray) {
			desc->sendToClient.returnType.type = GT_Custom_Handle;
			desc->sendToClient.returnType.customName = "DataList";
		}

		evtDescs.push_back(desc);
	}
}

void BindEventBinds(bool menu) {
	threads::Lock lock(eventDescMutex);

	foreach(it, evtDescs) {
		EventDesc& desc = **it;

		if(!devices.network->isClient) {
			if(desc.recvShadow)
				continue;
		}

		if(menu != desc.recvMenu)
			continue;

		Manager* man = 0;
		if(desc.recvMenu)
			man = devices.scripts.menu;
		else if(desc.recvEngine == "server" || desc.recvEngine == "shadow")
			man = devices.scripts.server;
		else
			man = devices.scripts.client;
		desc.recvManager = man;

		if(!desc.recvServer || desc.recvLocal || !devices.network->isClient) {
			desc.recvFunc = man->getFunction(desc.recvModule.c_str(),
						desc.recvCall.declaration(true).c_str());

			if(!desc.recvFunc) {
				if(desc.recvServer || desc.recvShadow) {
					desc.recvCall.prepend(GT_Player_Ref);
					desc.passPlayer = true;
					desc.recvFunc = man->getFunction(desc.recvModule.c_str(),
								desc.recvCall.declaration(true).c_str());
				}
				if(!desc.recvFunc) {
					error("Events: Could not find function %s::%s::%s",
						desc.recvEngine.c_str(), desc.recvModule.c_str(), 
						desc.recvCall.declaration(true).c_str());
					continue;
				}
			}
		}

		unsigned aCnt = desc.recvCall.argCount;
		for(unsigned i = 0; i < aCnt; ++i) {
			auto& arg = desc.recvCall.arguments[i];

			//Find the correct type id for the receiving function
			if(arg.type == GT_Custom_Handle) {
				std::string in_name = "Serializable";

				auto* mod = man->engine->GetModule(desc.recvModule.c_str());
				if(mod) {
					int cid = mod->GetTypeIdByDecl(arg.customName.c_str());
					arg.customType = (void*)man->engine->GetTypeInfoById(cid);
				}

				asITypeInfo *rcvType, *srType, *clType;
				if(desc.recvMenu) {
					rcvType = man->engine->GetTypeInfoByName(in_name.c_str());
					srType = man->engine->GetTypeInfoByName(in_name.c_str());
					clType = man->engine->GetTypeInfoByName(in_name.c_str());
				}
				else {
					rcvType = man->engine->GetTypeInfoByName(in_name.c_str());
					srType = devices.scripts.server->engine->GetTypeInfoByName(in_name.c_str());
					clType = devices.scripts.client->engine->GetTypeInfoByName(in_name.c_str());
				}

				if(!srType || !clType || !rcvType) {
					error("Error: Could not find interface type '%s'.", in_name.c_str());
				}
				else {
					arg.customRead = (void*)rcvType->GetMethodByDecl("void read(Message&)");
					arg.customWrite = (void*)rcvType->GetMethodByDecl("void write(Message&)");

					unsigned r = i;
					if(desc.recvServer && desc.passPlayer)
						--r;

					desc.sendToClient.arguments[r+1].customWrite = (void*)srType->GetMethodByDecl("void write(Message&)");

					desc.sendToServer.arguments[r].customType = arg.customType;
					desc.sendToServer.arguments[r].customRead = arg.customRead;
					desc.sendToServer.arguments[r].customWrite = (void*)clType->GetMethodByDecl("void write(Message&)");
				}

				if(!arg.customType) {
					error("Error: Could not find class '%s' in module '%s' for event description.",
						arg.customName.c_str(), desc.recvModule.c_str());
				}
			}
		}
	}
}

Player ALL_PLAYERS(-1);
Player SERVER_PLAYER(-2);

GenericValue handleSendToServer(void* arg, GenericCallData& args) {
	GenericValue retVal;
	EventDesc& desc = *(EventDesc*)arg;
	args.desc = desc.sendToServer;

	if(desc.recvLocal || !devices.network->isClient) {
		if(desc.recvFunc && desc.recvManager) {
			//Transfer custom classes from one engine to the other
			if(desc.onlyPrimitive) {
				Call cl = desc.recvManager->call(desc.recvFunc);

				//Append player argument
				if(desc.passPlayer)
					cl.push(&devices.network->currentPlayer);

				//Append other arguments
				args.pushTo(cl);

				retVal = desc.recvCall.call(cl);
			}
			else {
				net::Message msg(net::MT_Application, net::MF_Managed);
				std::vector<asIScriptObject*> resultObjects;

				for(unsigned i = 0; i < args.desc.argCount; ++i) {
					auto& arg = args.desc.arguments[i];
					if(arg.type != GT_Custom_Handle)
						continue;

					if(!arg.customWrite || !arg.customRead || !arg.customType || !desc.recvManager)
						continue;

					//Write to message
					{
						scripts::Call cl = getActiveManager()->call((asIScriptFunction*)arg.customWrite);
						cl.setObject((asIScriptObject*)args.values[i].ptr);
						cl.push(&msg);
						cl.call();
					}

					//Create object
					asITypeInfo* type = (asITypeInfo*)arg.customType;
					asIScriptObject* ret = (asIScriptObject*)desc.recvManager->engine->CreateScriptObject(type);

					//Call read function
					{
						scripts::Call cl = desc.recvManager->call((asIScriptFunction*)arg.customRead);
						cl.setObject(ret);
						cl.push(&msg);
						cl.call();
					}

					msg.reset();
					resultObjects.push_back(ret);
				}

				Call cl = desc.recvManager->call(desc.recvFunc);

				//Append player argument
				if(desc.passPlayer)
					cl.push(&devices.network->currentPlayer);

				//Append other arguments
				unsigned customIndex = 0;
				auto transferCustom = [&](ArgumentDesc& arg, asIScriptObject* ptr) -> asIScriptObject* {
					return resultObjects[customIndex++];
				};

				args.pushTo(cl, 0, transferCustom);
				retVal = desc.recvCall.call(cl);
			}
		}
	}
	else {
		auto writeCustom = [](net::Message& msg, ArgumentDesc& adesc, GenericValue& val) {
			if(adesc.type != GT_Custom_Handle)
				return;

			if(adesc.customWrite) {
				//Call write function
				scripts::Call cl = getActiveManager()->call((asIScriptFunction*)adesc.customWrite);
				cl.setObject(val.script);
				cl.push(&msg);
				cl.call();
			}
			else {
				error("Could not find custom write for argument.");
			}
		};

		net::Message msg(MT_Event_Call, net::MF_Managed);
		msg << desc.id;
		args.write(msg, 0, writeCustom);

		devices.network->send(msg);
	}

	return retVal;
}

GenericValue handleSendToClient_local(void* arg, GenericCallData& args) {
	EventDesc& desc = *(EventDesc*)arg;
	args.desc = desc.sendToServer;

	auto writeCustom = [&](net::Message& msg, ArgumentDesc& adesc, GenericValue& val) {
		if(adesc.customWrite) {
			//Call write function
			scripts::Call cl = devices.scripts.server->call((asIScriptFunction*)adesc.customWrite);
			cl.setObject(val.script);
			cl.push(&msg);
			cl.call();
		}
	};

	net::Message msg(MT_Event_Call, net::MF_Managed);
	msg << desc.id;
	args.write(msg, 0, writeCustom);
	
	msg.finalize();
	msg.rewind();
	handleEventMessage(&devices.network->currentPlayer, msg);
	return GenericValue();
}

GenericValue handleSendToClient(void* arg, GenericCallData& args) {
	EventDesc& desc = *(EventDesc*)arg;
	Player* pl = args.values[0].player;
	args.desc = desc.sendToClient;

	auto writeCustom = [&](net::Message& msg, ArgumentDesc& adesc, GenericValue& val) {
		if(adesc.customWrite) {
			//Call write function
			scripts::Call cl = devices.scripts.server->call((asIScriptFunction*)adesc.customWrite);
			cl.setObject(val.script);
			cl.push(&msg);
			cl.call();
		}
	};

	net::Message msg(MT_Event_Call, net::MF_Managed);
	msg << desc.id;
	args.write(msg, 1, writeCustom);
	
	if(!devices.network->isServer || pl == nullptr || pl == &devices.network->currentPlayer) {
		msg.finalize();
		msg.rewind();
		handleEventMessage(&devices.network->currentPlayer, msg);
	}
	else if(pl == &ALL_PLAYERS || pl->id == -1) {
		devices.network->sendAll(msg);
		handleEventMessage(&devices.network->currentPlayer, msg);
	}
	else
		devices.network->send(pl, msg);

	return GenericValue();
}

threads::Mutex queuedEventLock;
std::stack<std::tuple<Player,net::Message*>> queuedClientEvents;
void processEvents() {
	while(!queuedClientEvents.empty()) {
		queuedEventLock.lock();
		auto item = queuedClientEvents.top();
		queuedClientEvents.pop();
		queuedEventLock.release();

		handleEventMessage(&std::get<0>(item), *std::get<1>(item));
		delete std::get<1>(item);
	}
}

scripts::Manager* handleEventMessage(Player* from, net::Message& msg, bool interceptMenu) {
	int eventId;
	msg >> eventId;

	if(eventId < 0 || eventId >= (int)evtDescs.size())
		return nullptr;

	EventDesc& edesc = *evtDescs[eventId];
	if(interceptMenu && edesc.recvMenu)
		return edesc.recvManager;

	if(!edesc.recvMenu && !game_running) {
		msg.rewind();
		threads::Lock lock(queuedEventLock);
		queuedClientEvents.push(std::tuple<Player,net::Message*>(*from,new net::Message(msg)));
		return nullptr;
	}

	GenericCallDesc& cdesc = edesc.recvCall;
	GenericCallData data(cdesc);

	auto readCustom = [edesc](net::Message& msg, ArgumentDesc& desc, GenericValue& val) {
		if(desc.customType && desc.customRead && edesc.recvManager) {
			//Create object
			asITypeInfo* type = (asITypeInfo*)desc.customType;
			val.script = (asIScriptObject*)edesc.recvManager->engine->CreateScriptObject(type);

			//Call read function
			scripts::Call cl = edesc.recvManager->call((asIScriptFunction*)desc.customRead);
			cl.setObject(val.script);
			cl.push(&msg);
			cl.call();
		}
	};

	if((edesc.recvServer || edesc.recvShadow) && edesc.passPlayer) {
		data.values[0].player = from;
		data.read(msg, 1, readCustom);
	}
	else {
		data.read(msg, 0, readCustom);
	}

	if(edesc.recvFunc && edesc.recvManager) {
		Call cl = edesc.recvManager->call(edesc.recvFunc);
		data.pushTo(cl);
		cl.call();
	}

	return nullptr;
}

static void linkEmpire(Player& inPl, Empire* emp) {
	threads::ReadLock lock(devices.network->playerLock);
	Player* pl = devices.network->getPlayer(inPl.id);
	if(!pl)
		return;
	if(pl->emp && pl->emp != Empire::getSpectatorEmpire()) {
		pl->emp->player = nullptr;
		pl->emp->lastPlayer = net::Address();
	}
	pl->emp = emp;
	pl->changedEmpire = true;
	pl->controlMask = 0;
	pl->viewMask = ~0;
	if(emp && emp != Empire::getSpectatorEmpire()) {
		emp->player = pl;
		emp->lastPlayer = pl->address;
		pl->controlMask = emp->mask;
		pl->viewMask = emp->mask;
	}
}

static bool playerEquals(Player& player, Player& other) {
	return player.id == other.id;
}

static asITypeInfo* getPlayerArrayType() {
	return (asITypeInfo*)asGetActiveContext()->GetEngine()->GetUserData(EDID_playerArray);
}

static CScriptArray* getPlayers() {
	CScriptArray* results = new CScriptArray(0, getPlayerArrayType());
	results->Reserve(devices.network->players.size());

	{
		threads::ReadLock lock(devices.network->playerLock);
		foreach(it, devices.network->players)
			results->InsertLast(&it->second);
	}

	return results;
}

static Player* getPlayer(int id) {
	return devices.network->getPlayer(id);
}

static std::string playerName(Player& player) {
	return std::string(player.nickname);
}

static void ctor_addr(void* mem) {
	new(mem) net::Address();
}

static void ctor_addrv(void* mem, const std::string& hostname, int port) {
	new(mem) net::Address(hostname, port);
}

static net::Address& cpy_addr(net::Address& into, const net::Address& from) {
	into = from;
	return into;
}

static bool eq_addr(const net::Address& addr, const net::Address& other) {
	return addr == other;
}

static void dtor_addr(net::Address& addr) {
	addr.~Address();
}

static void ctor_game(void* mem) {
	new(mem) net::Game();
}

static net::Game& cpy_game(net::Game& into, const net::Game& from) {
	into = from;
	return into;
}

static void dtor_game(net::Game& addr) {
	addr.~Game();
}

static void queryServers() {
	devices.network->queryServers();
}

static bool isQuerying() {
	return devices.network->query && devices.network->query->updating;
}

static void getQueriedServers(CScriptArray* arr) {
	threads::Mutex mtx(devices.network->queryMtx);
	std::vector<net::Game>& list = devices.network->queryResult;
	foreach(it, list)
		arr->InsertLast(&(*it));
	list.clear();
}

static void mpKick(int playerId) {
	devices.network->kick(playerId);
}

static void mpConnect(net::Game& game, bool disablePunchthrough, const std::string& pwd) {
	devices.network->connect(game, disablePunchthrough, pwd);
}

static void hostGame(const std::string& gamename, int port, unsigned maxPlayers, bool isPublic, bool punchthrough, const std::string& password) {
	devices.network->host(gamename, port, maxPlayers, isPublic, punchthrough, password);
}

static unsigned dcReason() {
	return devices.network->disconnection;
}

static float glxProgress() {
	return devices.network->galaxyProgress;
}

static bool glxAwaiting() {
	return devices.network->isClient && devices.network->serverReady &&
		!devices.network->currentPlayer.hasGalaxy;
}

class IsolateAction : public processing::Action {
	asIScriptObject* obj;
public:
	IsolateAction(asIScriptObject* object) : obj(object) {}

	bool run() {
		auto* func = obj->GetObjectType()->GetMethodByDecl("void call()");
		if(func) {
			auto& mana = scripts::Manager::fromEngine(obj->GetEngine());
			auto call = mana.call(func);
			call.setObject(obj);
			call.call();
		}
		return true;
	}
	
	~IsolateAction() {
		obj->Release();
	}
};

static void runIsolate(asIScriptObject* obj) {
	if(obj == nullptr)
		return;
	auto* act = new IsolateAction(obj);
	processing::queueIsolationAction(act);
}

void RegisterEventBinds(bool server, bool shadow, bool menu) {
	threads::Lock lock(eventDescMutex);

	ClassBind player("Player", asOBJ_REF | asOBJ_NOCOUNT, 0);
	player.addMember("const int id", offsetof(Player, id));
	player.addMember("Empire@ emp", offsetof(Player, emp));
	if(server) {
		player.addMember("uint controlMask", offsetof(Player, controlMask));
		player.addMember("uint viewMask", offsetof(Player, viewMask));
	}
	else {
		player.addMember("const uint controlMask", offsetof(Player, controlMask));
		player.addMember("const uint viewMask", offsetof(Player, viewMask));
	}
	player.addMethod("bool controls(Empire& emp)", asMETHOD(Player, controls));
	player.addMethod("bool views(Empire& emp)", asMETHOD(Player, views));
	player.addExternMethod("string get_name()", asFUNCTION(playerName));
	player.addExternMethod("bool opEquals(const Player& other) const", asFUNCTION(playerEquals));
	if(server)
		player.addExternMethod("void linkEmpire(Empire@ empire)", asFUNCTION(linkEmpire));

	bindGlobal("const Player ALL_PLAYERS", &ALL_PLAYERS);
	bindGlobal("const Player SERVER_PLAYER", &SERVER_PLAYER);
	bindGlobal("Player CURRENT_PLAYER", &devices.network->currentPlayer);
	bind("array<Player@>@ getPlayers()", asFUNCTION(getPlayers));
	bind("Player@ getPlayer(int id)", asFUNCTION(getPlayer));

	ClassBind ga("GameAddress", asOBJ_VALUE | asOBJ_APP_CLASS_CDA, sizeof(net::Address));
	ga.addConstructor("void f()", asFUNCTION(ctor_addr));
	ga.addConstructor("void f(const string& hostname, int port = 2048)", asFUNCTION(ctor_addrv));
	ga.addDestructor("void f()", asFUNCTION(dtor_addr));
	ga.addExternMethod("GameAddress& opAssign(const GameAddress& other)", asFUNCTION(cpy_addr));
	ga.addExternMethod("bool opEquals(const GameAddress& other) const", asFUNCTION(eq_addr));
	ga.addMember("int port", offsetof(net::Address, port));
	ga.addMethod("string toString(bool showPort = true) const", asMETHOD(net::Address, toString));

	ClassBind gs("GameServer", asOBJ_VALUE | asOBJ_APP_CLASS_CDA, sizeof(net::Game));
	gs.addConstructor("void f()", asFUNCTION(ctor_game));
	gs.addDestructor("void f()", asFUNCTION(dtor_game));
	gs.addExternMethod("GameServer& opAssign(const GameServer& other)", asFUNCTION(cpy_game));
	gs.addMember("GameAddress address", offsetof(net::Game, address));
	gs.addMember("string name", offsetof(net::Game, name));
	gs.addMember("string mod", offsetof(net::Game, mod));
	gs.addMember("uint16 players", offsetof(net::Game, players));
	gs.addMember("uint16 maxPlayers", offsetof(net::Game, maxPlayers));
	gs.addMember("int punchPort", offsetof(net::Game, punchPort));
	gs.addMember("int version", offsetof(net::Game, version));
	gs.addMember("bool started", offsetof(net::Game, started));
	gs.addMember("bool isLocal", offsetof(net::Game, isLocal));
	gs.addMember("bool password", offsetof(net::Game, password));
	player.addMember("GameAddress address", offsetof(Player, address));

	EnumBind dr("DisconnectReason");
	dr["DR_Timeout"] = net::DR_Timeout;
	dr["DR_Error"] = net::DR_Error;
	dr["DR_Close"] = net::DR_Close;
	dr["DR_Kick"] = net::DR_Kick;
	dr["DR_Version"] = net::DR_Version;
	dr["DR_Password"] = net::DR_Password;

	bind("DisconnectReason get_mpDisconnectReason()", asFUNCTION(dcReason));
	bind("float get_galaxySendProgress()", asFUNCTION(glxProgress));
	bind("bool get_awaitingGalaxy()", asFUNCTION(glxAwaiting));
	bind("void mpQueryServers()", asFUNCTION(queryServers));
	bind("bool mpIsQuerying()", asFUNCTION(isQuerying));
	bind("void mpGetServers(array<GameServer>& list)", asFUNCTION(getQueriedServers));
	bind("void mpKick(int playerId)", asFUNCTION(mpKick));
	bind("void mpHost(const string& gamename = \"\", uint port = 2048, uint maxPlayers = 0, bool isPublic = true, bool punchthrough = true, const string& password = \"\")",
			asFUNCTION(hostGame));
	bind("void mpConnect(const GameServer& game, bool disablePunchthrough = false, const string& password = \"\")", asFUNCTION(mpConnect));

	if(void* plArray = getEngine()->GetTypeInfoById(getEngine()->GetTypeIdByDecl("array<Player@>")))
		getEngine()->SetUserData(plArray, EDID_playerArray);

	if(server) {
		if(!shadow)
			bindGlobal("Player HOST_PLAYER", &devices.network->currentPlayer);
	}
	bindGlobal("int MP_VERSION", &NetworkManager::MP_VERSION);

	foreach(it, evtDescs) {
		EventDesc* desc = *it;
		if(desc->recvMenu && !menu)
			continue;

		//Register the functions to send
		if(server) {
			if(!desc->recvServer) {
				if(shadow)
					bindGeneric(desc->sendToServer, handleSendToClient_local, desc, true);
				else
					bindGeneric(desc->sendToClient, handleSendToClient, desc, true);
			}
		}
		else if(menu && desc->recvMenu) {
			if(desc->recvServer)
				bindGeneric(desc->sendToServer, handleSendToServer, desc, true);
			else
				bindGeneric(desc->sendToClient, handleSendToClient, desc, true);
		}
		else {
			if(desc->recvServer)
				bindGeneric(desc->sendToServer, handleSendToServer, desc, true);
		}

	}

	//Adding console commands
	InterfaceBind isolateClass("IsolateHook");
	isolateClass.addMethod("void call()");
	bind("void isolate_run(IsolateHook@ hook)", asFUNCTION(runIsolate));
}

};
