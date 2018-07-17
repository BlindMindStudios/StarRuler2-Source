#pragma once
#include "angelscript.h"
#include "util/refcount.h"
#include "rect.h"
#include "scripts/script_bind.h"
#include "network/message.h"
#include <map>

struct Player;
struct Image;
class Object;
class SaveMessage;
namespace net { struct Message; };

namespace scripts {
	class Manager;
	void RegisterServerBinds(asIScriptEngine* engine);
	void RegisterClientBinds(asIScriptEngine* engine);
	void RegisterMenuBinds(asIScriptEngine* engine);
	void RegisterShadowBinds(asIScriptEngine* engine);

	void RegisterObjectDefinitions();
	void RegisterObjectBinds(bool declarations, bool server, bool shadow);
	void RegisterEmpireBinds(bool declarations, bool server);
	void RegisterDesignBinds(bool server, bool declarations);
	void RegisterGeneralBinds(bool server, bool shadow);
	void RegisterGuiBinds();
	void RegisterDataBinds();
	void RegisterThreadingBinds();
	void RegisterRenderBinds(bool decl, bool isMenu, bool server);
	void RegisterParticleSystemBinds();
	void RegisterProfileBinds();
	void RegisterInspectionBinds();
	void RegisterMenuBinds(bool ingame);
	void RegisterJoystickBinds();
	void RegisterObjectCreation(bool declarations);
	void RegisterEventBinds(bool server, bool shadow, bool menu);
	void RegisterSoundBinds();
	void RegisterDynamicTypes(bool server);
	void RegisterNetworkBinds(bool server);
	void RegisterDatafiles();
	void RegisterScriptHooks();
	void RegisterFormulaBinds(bool server);
	void RegisterSaveFileBinds(bool server, bool decl);
	void RegisterJSONBinds();
	void RegisterWebBinds();
	void RegisterIRCBinds();

	void buildEmpAttribIndices();
	void SetObjectTypeOffsets();

	void LoadScriptHooks(const std::string& filename);

	void ClearEvents();
	void ReadEvents(const std::string& filename);
	void BindEventBinds(bool menu = false);

	scripts::Manager* handleEventMessage(Player* from, net::Message& msg, bool interceptMenu = false);
	void handleObjectComponentMessage(Player* from, net::Message& msg);
	void handleEmpireComponentMessage(Player* from, net::Message& msg);
	bool isAccessible(const std::string& filename);

	void addNamespaceState();

	void setClip(const recti& clip);
	void resetClip();
	recti* getClip();

	struct ScriptImage;
	ScriptImage* makeScriptImage(Image* img);

	struct YieldedMessage {
		net::Message msg;
		YieldedMessage* next;
		bool written;
		bool read;

		YieldedMessage()
			: next(0), written(false), read(false) {
		}
	};

	SaveMessage& saveObject(SaveMessage& msg, Object* obj);
	SaveMessage& loadObject(SaveMessage& msg, Object** obj);

	struct ObjectDesc;
	Object* makeObject(ObjectDesc& desc);

	YieldedMessage* StartYieldContext();
	void EndYieldContext();

	void scr_loadGame(const std::string& fname);

	//Specialized array used to send objects to scripts
	struct ObjArray : public AtomicRefCounted {
		std::vector<Object*> objs;

		ObjArray();
		ObjArray(unsigned count);
		static ObjArray* create();
		static ObjArray* create_n(unsigned count);
		void operator=(const ObjArray& other);
		bool empty() const;
		unsigned size() const;
		void reserve(unsigned size);
		void resize(unsigned size);
		void clear();
		Object*& operator[](unsigned index);
		Object*& last();
		Object* index_value(unsigned index);
		Object* last_value();
		void erase(unsigned index);
		void insert(unsigned index, Object* obj);
		void push_back(Object* obj);
		void pop_back();
		void sortAsc_bound(unsigned lower, unsigned upper);
		void sortAsc();
		void sortDesc_bound(unsigned lower, unsigned upper);
		void sortDesc();
		int find(const Object* obj) const;
		void remove(const Object* obj);
		int findSorted(const Object* obj) const;
		void removeSorted(const Object* obj);
	};
};

void writeObject(net::Message& msg, Object* obj, bool includeType = true);
Object* readObject(net::Message& msg, bool create = true, int knownType = -1);
