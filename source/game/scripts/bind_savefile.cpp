#include "binds.h"
#include "scriptarray.h"
#include "main/references.h"
#include "main/logging.h"
#include "design/design.h"
#include "network/message.h"
#include "util/elevation_map.h"
#include "util/save_file.h"
#include "threads.h"
#include "color.h"
#include "empire.h"

namespace scripts {

static inline asITypeInfo* getSavable(asIScriptEngine* engine) {
	return (asITypeInfo*)engine->GetUserData(EDID_SavableType);
}

static inline asIScriptFunction* getSavableWrite(asIScriptEngine* engine) {
	return (asIScriptFunction*)engine->GetUserData(EDID_SavableWrite);
}

static inline asIScriptFunction* getSavableRead(asIScriptEngine* engine) {
	return (asIScriptFunction*)engine->GetUserData(EDID_SavableRead);
}

static void createSaveMessage(void* mem) {
	scripts::throwException("Don't instantiate savefiles manually.");
}

static void destroyMessage(SaveMessage& msg) {
	msg.~SaveMessage();
}

static net::msize_t reserveInt(SaveMessage& msg) {
	try {
		return msg.reserve<int>();
	}
	catch(...) {
		scripts::throwException("Message needs to be aligned before reserving space.");
		return 0;
	}
}

static void fillInt(SaveMessage& msg, net::msize_t pos, int value) {
	msg.fill<int>(pos, value);
}

static void msgDumpRead(SaveMessage& msg) {
	SaveMessage::Position pos = msg.getReadPosition();
	print("Read position: %d bytes, %d bits", pos.bytes, pos.bits);
}

static void msgDumpWrite(SaveMessage& msg) {
	SaveMessage::Position pos = msg.getWritePosition();
	print("Write position: %d bytes, %d bits", pos.bytes, pos.bits);
}

static void writeSerial(SaveMessage& msg, asIScriptObject* serial) {
	if(serial == 0) {
		scripts::throwException("Null Savable@ when writing");
		return;
	}

	scripts::Manager& manager = scripts::Manager::fromEngine(serial->GetEngine());
	Call cl = manager.call(getSavableWrite(manager.engine));
	cl.setObject(serial);
	cl.push(&msg);
	cl.call();

	serial->Release();
}

static void readSerial(SaveMessage& msg, asIScriptObject* serial) {
	if(serial == 0) {
		scripts::throwException("Null Savable@ when reading");
		return;
	}

	scripts::Manager& manager = scripts::Manager::fromEngine(serial->GetEngine());
	Call cl = manager.call(getSavableRead(manager.engine));
	cl.setObject(serial);
	cl.push(&msg);
	cl.call();

	serial->Release();
}

static SaveMessage& readElevation(SaveMessage& msg, ElevationMap& emap) {
	msg >> emap.generated;
	msg >> emap.gridStart;
	msg >> emap.gridSize;
	msg >> emap.gridInterval;
	msg >> emap.gridResolution;

	unsigned size = emap.gridResolution.x * emap.gridResolution.y;
	emap.grid = (float*)calloc(size, sizeof(float));
	try {
		msg.readBits((uint8_t*)emap.grid, size * sizeof(float) * 8);
	}
	catch(net::MessageReadError) {
		scripts::throwException("Error reading from message: end of message.");
	}
	return msg;
}

static SaveMessage& writeElevation(SaveMessage& msg, ElevationMap& emap) {
	msg << emap.generated;
	msg << emap.gridStart;
	msg << emap.gridSize;
	msg << emap.gridInterval;
	msg << emap.gridResolution;

	unsigned size = emap.gridResolution.x * emap.gridResolution.y;
	msg.writeBits((uint8_t*)emap.grid, size * sizeof(float) * 8);
	return msg;
}

SaveMessage& loadObject(SaveMessage& msg, Object** obj) {
	int id;

	try {
		msg >> id;
	}
	catch(net::MessageReadError) {
		scripts::throwException("Error reading from message: end of message.");
		return msg;
	}

	if(Object* prev = *obj)
		prev->drop();

	*obj = getObjectByID(id, true);
	return msg;
}

Object* readObject_e(SaveMessage& msg) {
	Object* obj = nullptr;
	loadObject(msg, &obj);
	return obj;
}

SaveMessage& saveObject(SaveMessage& msg, Object* obj) {
	if(obj) {
		msg << obj->id;
	}
	else {
		int id = 0;
		msg << id;
	}
	return msg;
}

SaveMessage& readEmpire(SaveMessage& msg, Empire** emp) {
	unsigned char empID;

	try {
		msg >> empID;
	}
	catch(net::MessageReadError) {
		scripts::throwException("Error reading from message: end of message.");
		return msg;
	}

	*emp = Empire::getEmpireByID(empID);
	return msg;
}

SaveMessage& writeEmpire(SaveMessage& msg, Empire* emp) {
	if(emp)
		msg << emp->id;
	else
		msg << INVALID_EMPIRE;
	return msg;
}

static SaveMessage& readDesign(SaveMessage& msg, const Design** dsg) {
	unsigned char empID;

	if(auto* prev = *dsg) {
		prev->drop();
		prev = 0;
	}

	try {
		msg >> empID;
		if(empID == 0) {
			*dsg = 0;
			return msg;
		}

		Empire* emp = Empire::getEmpireByID(empID);
		if(!emp) {
			*dsg = 0;
			return msg;
		}

		int dsgID;
		msg >> dsgID;

		*dsg = emp->getDesign(dsgID, true);
	}
	catch(net::MessageReadError) {
		scripts::throwException("Error reading from message: end of message.");
		return msg;
	}

	return msg;
}

static SaveMessage& writeDesign(SaveMessage& msg, const Design** dsg) {
	if(*dsg) {
		if(!(*dsg)->owner) {
			unsigned char empID = 0;
			msg << empID;
			scripts::throwException("Cannot transmit design without owner.");
			return msg;
		}

		msg << (*dsg)->owner->id;
		msg << (*dsg)->id;
	}
	else {
		unsigned char empID = 0;
		msg << empID;
	}
	return msg;
}

static bool wrapReadBit(SaveMessage& msg) {
	try {
		return msg.readBit();
	}
	catch(net::MessageReadError) {
		scripts::throwException("Error reading from message: end of message.");
	}
	return false;
}

static void wrapReadAlign(SaveMessage& msg) {
	try {
		msg.readAlign();
	}
	catch(net::MessageReadError) {
		scripts::throwException("Error aligning message: end of message.");
	}
}

template<class T>
static SaveMessage& wrapRead(SaveMessage& msg, T& value) {
	try {
		msg >> value;
	}
	catch(net::MessageReadError) {
		scripts::throwException("Error reading from message: end of message.");
	}
	return msg;
}

static unsigned getScriptVersion(SaveMessage& msg) {
	return msg.file.scriptVersion;
}

static void setScriptVersion(SaveMessage& msg, unsigned version) {
	msg.file.scriptVersion = version;
}

static unsigned getStartVersion(SaveMessage& msg) {
	return msg.file.startVersion;
}

static void setStartVersion(SaveMessage& msg, unsigned version) {
	msg.file.startVersion = version;
}

static void addIdentifier(SaveMessage& msg, unsigned type, int id, const std::string& ident) {
	if(!msg.file.addIdentifier(type, id, ident))
		scripts::throwException(format("Duplicate identifier: '$1'.", ident.c_str()).c_str());
}

static int readIdentifier(SaveMessage& msg, unsigned type) {
	int id;
	msg >> id;

	return msg.file.getIdentifier(type, id);
}

static int getIdentifier(SaveMessage& msg, unsigned type, unsigned id) {
	return msg.file.getIdentifier(type, id);
}

static void writeIdentifier(SaveMessage& msg, unsigned type, int id) {
	msg << id;
}

static unsigned getIdentifierCount(SaveMessage& msg, unsigned type) {
	return msg.file.getIdentifierCount(type);
}

static unsigned getPrevIdentifierCount(SaveMessage& msg, unsigned type) {
	return msg.file.getPrevIdentifierCount(type);
}

static int saveCmp(SaveMessage& msg, unsigned version) {
	if(version > msg.file.scriptVersion)
		return -1;
	else if(version < msg.file.scriptVersion)
		return 1;
	else
		return 0;
}

void RegisterSaveFileBinds(bool server, bool decl) {
	if(decl) {
		ClassBind msg("SaveFile", asOBJ_VALUE | asOBJ_APP_CLASS_CDA, sizeof(SaveMessage));
		return;
	}

	InterfaceBind inf("Savable");

	//Message manipulation
	ClassBind msg("SaveFile");
	msg.addConstructor("void f()", asFUNCTION(createSaveMessage));
	msg.addDestructor("void f()", asFUNCTION(destroyMessage));
	msg.addMethod("void dump() const", asMETHOD(SaveMessage, dump));
	msg.addMethod("uint get_size() const", asMETHOD(SaveMessage, size));

	msg.addExternMethod("void set_scriptVersion(uint version)", asFUNCTION(setScriptVersion));
	msg.addExternMethod("uint get_scriptVersion()", asFUNCTION(getScriptVersion));

	msg.addExternMethod("void set_startVersion(uint version)", asFUNCTION(setStartVersion));
	msg.addExternMethod("uint get_startVersion()", asFUNCTION(getStartVersion));

	msg.addExternMethod("void addIdentifier(uint type, int id, const string&in ident)", asFUNCTION(addIdentifier));
	msg.addExternMethod("uint readIdentifier(uint type)", asFUNCTION(readIdentifier));
	msg.addExternMethod("int getIdentifier(uint ident, int id)", asFUNCTION(getIdentifier));
	msg.addExternMethod("void writeIdentifier(uint type, int id)", asFUNCTION(writeIdentifier));
	msg.addExternMethod("uint getIdentifierCount(uint type)", asFUNCTION(getIdentifierCount));
	msg.addExternMethod("uint getPrevIdentifierCount(uint type)", asFUNCTION(getPrevIdentifierCount));

	msg.addExternMethod("int opCmp(uint version)", asFUNCTION(saveCmp));

	msg.addExternMethod("uint reserve()", asFUNCTION(reserveInt));
	msg.addExternMethod("void fill(uint, int)", asFUNCTION(fillInt));

	msg.addMethod("void writeBit(bool)", asMETHOD(SaveMessage, writeBit));
	msg.addMethod("void write1()", asMETHOD(SaveMessage, write1));
	msg.addMethod("void write0()", asMETHOD(SaveMessage, write0));
	msg.addExternMethod("bool readBit()", asFUNCTION(wrapReadBit));

	msg.addExternMethod("void readAlign()", asFUNCTION(wrapReadAlign));
	msg.addMethod("void writeAlign()", asMETHOD(SaveMessage, writeAlign));

	msg.addExternMethod("void dumpReadPosition()", asFUNCTION(msgDumpRead));
	msg.addExternMethod("void dumpWritePosition()", asFUNCTION(msgDumpWrite));

	msg.addExternMethod("Message& opShl(Savable@)", asFUNCTION(writeSerial));
	msg.addExternMethod("Message& opShr(Savable@)", asFUNCTION(readSerial));

	msg.addMethod("SaveFile& opShl(bool)",
		asMETHODPR(net::Message, operator<<, (bool), net::Message&));

	msg.addExternMethod("SaveFile& opShr(bool&)",
		asFUNCTION(wrapRead<bool>));

#define BIND_TYPE(stype, rtype)\
	msg.addMethod("SaveFile& opShl(" #stype "&)",\
		asMETHODPR(net::Message, operator<<, (const rtype&), net::Message&));\
\
	msg.addExternMethod("SaveFile& opShr(" #stype "&)",\
		asFUNCTION(wrapRead<rtype>));

	BIND_TYPE(uint8, unsigned char);
	BIND_TYPE(uint16, unsigned short);
	BIND_TYPE(int8, char);
	BIND_TYPE(int16, short);
	BIND_TYPE(int64, int64_t);
	BIND_TYPE(int, int);
	BIND_TYPE(uint, unsigned);
	BIND_TYPE(float, float);
	BIND_TYPE(double, double);
	BIND_TYPE(string, std::string);
	BIND_TYPE(Color, Color);
	BIND_TYPE(vec3d, vec3d);
	BIND_TYPE(vec3f, vec3f);
	BIND_TYPE(vec3i, vec3i);
	BIND_TYPE(vec2d, vec2d);
	BIND_TYPE(vec2u, vec2u);
	BIND_TYPE(vec2i, vec2i);
	BIND_TYPE(vec2f, vec2f);
	BIND_TYPE(quaterniond, quaterniond);
	BIND_TYPE(locked_int, int);
	BIND_TYPE(locked_double, double);

	msg.addExternMethod("SaveFile& opShl(ElevationMap&)", asFUNCTION(writeElevation));
	msg.addExternMethod("SaveFile& opShr(ElevationMap&)", asFUNCTION(readElevation));

	msg.addExternMethod("SaveFile& opShl(Object@+)", asFUNCTION(saveObject));
	msg.addExternMethod("SaveFile& opShr(Object@&)", asFUNCTION(loadObject));
	msg.addExternMethod("Object@ readObject()", asFUNCTION(readObject_e));

	msg.addExternMethod("SaveFile& opShl(Empire@)", asFUNCTION(writeEmpire));
	msg.addExternMethod("SaveFile& opShr(Empire@&)", asFUNCTION(readEmpire));

	msg.addExternMethod("SaveFile& opShl(const Design@&)", asFUNCTION(writeDesign));
	msg.addExternMethod("SaveFile& opShr(const Design@&)", asFUNCTION(readDesign));

	//Savable interface
	inf.addMethod("void load(SaveFile& file)");
	inf.addMethod("void save(SaveFile& file)");

	EnumBind glob("SaveGlobals");
	glob["SAVE_IDENTIFIER_START"] = SI_SCRIPT_START;

	//Keep function pointers
	asITypeInfo* type = getEngine()->GetTypeInfoByName("Savable");

	if(type) {
		asIScriptEngine* engine = getEngine();
		engine->SetUserData(type, EDID_SavableType);
		engine->SetUserData(type->GetMethodByDecl("void save(SaveFile& file)"), EDID_SavableWrite);
		engine->SetUserData(type->GetMethodByDecl("void load(SaveFile& file)"), EDID_SavableRead);
	}
	else {
		error("ERROR: Problem registering Savable type interface.");
	}
}

};
