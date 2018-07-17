#include "binds.h"
#include "scriptarray.h"
#include "main/references.h"
#include "main/logging.h"
#include "design/design.h"
#include "network/message.h"
#include "network/network_manager.h"
#include "util/elevation_map.h"
#include "util/link_container.h"
#include "../as_addons/include/scriptarray.h"
#include "threads.h"
#include "color.h"
#include "empire.h"

Object* readObject(net::Message& msg, bool create, int knownType) {
	unsigned typeID = knownType >= 0 ? (unsigned)knownType : msg.readLimited(ObjectTypeCount-1);
	unsigned objID = msg.readSmall();

	if(objID)
		return getObjectByID((typeID << ObjectTypeBitOffset) | objID, create);
	else
		return 0;
}

void writeObject(net::Message& msg, Object* obj, bool includeType) {
	unsigned typeID = 0, objID = 0;
	if(obj) {
		unsigned id = obj->id;
		typeID = id >> ObjectTypeBitOffset;
		objID = id & ObjectIDMask;
	}

	if(includeType)
		msg.writeLimited(typeID, ObjectTypeCount-1);
	msg.writeSmall(objID);
}

namespace scripts {
net::Message& readObjectScr(net::Message& msg, Object** obj);

static inline asITypeInfo* getSerializable(asIScriptEngine* engine) {
	return (asITypeInfo*)engine->GetUserData(EDID_SerializableType);
}

static inline asIScriptFunction* getSerializableWrite(asIScriptEngine* engine) {
	return (asIScriptFunction*)engine->GetUserData(EDID_SerializableWrite);
}

static inline asIScriptFunction* getSerializableRead(asIScriptEngine* engine) {
	return (asIScriptFunction*)engine->GetUserData(EDID_SerializableRead);
}

static YieldedMessage END_CONTEXT;
static Threaded(YieldedMessage*) yieldLink = 0;

static void setNickname(const std::string& nick) {
	devices.network->setNickname(nick);
}

static void yield(asIScriptObject* obj) {
	if(yieldLink == 0) {
		throwException("No yield context active.");
		return;
	}

	YieldedMessage* msg;

	//Make a new message or reuse
	if(yieldLink->written) {
		msg = new YieldedMessage();
		yieldLink->next = msg;
	}
	else {
		msg = yieldLink;
	}

	//Get correct function to call
	Manager* man = getActiveManager();
	asIScriptFunction* func = getSerializableWrite(man->engine);

	//Call the function
	if(obj && func) {
		Call cl = man->call(func);
		cl.setObject(obj);
		cl.push(&msg->msg);
		cl.call();

		msg->msg.finalize();
	}

	msg->written = true;

	yieldLink = msg;
}

static void yieldObject(Object* obj) {
	if(yieldLink == 0) {
		throwException("No yield context active.");
		return;
	}

	YieldedMessage* msg;

	//Make a new message or reuse
	if(yieldLink->written) {
		msg = new YieldedMessage();
		yieldLink->next = msg;
	}
	else {
		msg = yieldLink;
	}

	//Call the function
	if(obj) {
		writeObject(msg->msg, obj);
		msg->msg.finalize();
	}

	msg->written = true;

	yieldLink = msg;
}

static net::Message* getYieldMessage() {
	if(yieldLink == 0) {
		throwException("No yield context active.");
		return 0;
	}

	YieldedMessage* msg;

	//Make a new message or reuse
	if(yieldLink->written) {
		msg = new YieldedMessage();
		yieldLink->next = msg;
	}
	else {
		msg = yieldLink;
	}

	yieldLink = msg;
	return &yieldLink->msg;
}

static void finalizeYield() {
	if(yieldLink == 0) {
		throwException("No yield context active.");
		return;
	}

	if(yieldLink->written) {
		throwException("Yielded message already finalized.");
		return;
	}

	yieldLink->msg.finalize();
	yieldLink->written = true;
}

static YieldedMessage* waitForMessage(YieldedMessage** ctx) {
	//Wait for the message to become ready
	YieldedMessage* msg = *ctx;

	if(msg == 0 || msg == &END_CONTEXT)
		return 0;

	while(
		//Wait for the next message
		(msg->read && msg->next == 0) ||
		//Wait for the currrent message to become ready
		(!msg->written && msg->next != &END_CONTEXT)
	) {
		threads::sleep(1);
	}

	//Skip to the next message if available
	if(msg->read) {
		*ctx = msg->next;
		msg = msg->next;
	}
	else if(!msg->written && msg->next == &END_CONTEXT)
		return 0;

	if(msg == &END_CONTEXT)
		return 0;

	msg->read = true;
	return msg;
}

static void readMessage(YieldedMessage* msg, asIScriptObject* obj) {
	//Get correct function to call
	Manager* man = getActiveManager();
	asIScriptFunction* func = getSerializableRead(man->engine);

	//Call the function
	if(obj && func) {
		Call cl = man->call(func);
		cl.setObject(obj);
		cl.push(&msg->msg);

		cl.call();
	}
}

static void continueMessage(YieldedMessage* msg, YieldedMessage** ctx) {
	//Move to the next message if available
	if(msg->next)
		*ctx = msg->next;

	//Delete old message
	delete msg;
}

static bool receive(YieldedMessage** ctx, asIScriptObject* obj) {
	YieldedMessage* msg = waitForMessage(ctx);
	if(!msg) {
		if(obj)
			obj->Release();
		return false;
	}

	readMessage(msg, obj);
	continueMessage(msg, ctx);

	if(obj)
		obj->Release();
	return true;
}

static bool receiveObject(YieldedMessage** ctx, Object** obj) {
	YieldedMessage* msg = waitForMessage(ctx);
	if(!msg)
		return false;

	readObjectScr(msg->msg, obj);
	continueMessage(msg, ctx);
	return true;
}

static void receiveArray(CScriptArray* arr, YieldedMessage** ctx) {
	if(!ctx || !*ctx)
		return;

	//Get correct interface to use
	Manager* man = getActiveManager();
	asITypeInfo* srtype = getSerializable(man->engine);

	//Check that our subtype is compatible
	int subTypeId = arr->GetElementTypeId();
	auto* subType = man->engine->GetTypeInfoById(subTypeId);
	if(!subType || !subType->Implements(srtype)) {
		scripts::throwException("Cannot sync into array of non-serializable objects.");
		return;
	}
	if(subTypeId & asTYPEID_OBJHANDLE) {
		scripts::throwException("Cannot sync into array of handles.");
		return;
	}

	//Do all the reading
	unsigned index = 0;
	for(;;) {
		YieldedMessage* msg = waitForMessage(ctx);
		if(!msg)
			break;

		if(arr->GetSize() <= index)
			arr->Resize(index+1);

		readMessage(msg, (asIScriptObject*)arr->At(index));
		continueMessage(msg, ctx);
		++index;
	}

	if(arr->GetSize() > index)
		arr->Resize(index);
}

YieldedMessage* StartYieldContext() {
	if(yieldLink != 0) {
		error("Error: cannot nest yield contexts.");
		return 0;
	}

	yieldLink = new YieldedMessage();
	return yieldLink;
}

void EndYieldContext() {
	if(yieldLink)
		yieldLink->next = &END_CONTEXT;
	yieldLink = 0;
}

static void createMessage(void* mem) {
	new(mem) net::Message();
}

static void copyMessage(void* mem, net::Message& other) {
	new(mem) net::Message(other);
}

static void destroyMessage(net::Message& msg) {
	msg.~Message();
}

static net::Message& assignMessage(net::Message& msg, net::Message& other) {
	msg = other;
	return msg;
}

static bool emptyMessage(net::Message& msg) {
	return msg.size() == 0;
}

static net::msize_t reserveInt(net::Message& msg) {
	try {
		return msg.reserve<int>();
	}
	catch(...) {
		scripts::throwException("Message needs to be aligned before reserving space.");
		return 0;
	}
}

static void fillInt(net::Message& msg, net::msize_t pos, int value) {
	msg.fill<int>(pos, value);
}

static void msgDumpRead(net::Message& msg) {
	net::Message::Position pos = msg.getReadPosition();
	print("Read position: %d bytes, %d bits", pos.bytes, pos.bits);
}

static void msgDumpWrite(net::Message& msg) {
	net::Message::Position pos = msg.getWritePosition();
	print("Write position: %d bytes, %d bits", pos.bytes, pos.bits);
}

static void writeSerial(net::Message& msg, asIScriptObject* serial) {
	if(serial == 0) {
		scripts::throwException("Null Serializable@ when writing");
		return;
	}

	scripts::Manager& manager = scripts::Manager::fromEngine(serial->GetEngine());
	Call cl = manager.call(getSerializableWrite(manager.engine));
	cl.setObject(serial);
	cl.push(&msg);
	cl.call();

	serial->Release();
}

static void readSerial(net::Message& msg, asIScriptObject* serial) {
	if(serial == 0) {
		scripts::throwException("Null Serializable@ when reading");
		return;
	}

	scripts::Manager& manager = scripts::Manager::fromEngine(serial->GetEngine());
	Call cl = manager.call(getSerializableRead(manager.engine));
	cl.setObject(serial);
	cl.push(&msg);
	cl.call();

	serial->Release();
}

static net::Message& readElevation(net::Message& msg, ElevationMap& emap) {
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

static net::Message& writeElevation(net::Message& msg, ElevationMap& emap) {
	msg << emap.generated;
	msg << emap.gridStart;
	msg << emap.gridSize;
	msg << emap.gridInterval;
	msg << emap.gridResolution;

	unsigned size = emap.gridResolution.x * emap.gridResolution.y;
	msg.writeBits((uint8_t*)emap.grid, size * sizeof(float) * 8);
	return msg;
}

net::Message& readObjectScr(net::Message& msg, Object** obj) {
	Object* newObj = 0;

	try {
		newObj = readObject(msg);
	}
	catch(net::MessageReadError) {
		scripts::throwException("Error reading from message: end of message.");
		return msg;
	}

	if(Object* prev = *obj)
		prev->drop();
	*obj = newObj;
	return msg;
}

Object* readObject_e(net::Message& msg) {
	Object* obj = nullptr;
	readObjectScr(msg, &obj);
	return obj;
}

net::Message& writeObjectScr(net::Message& msg, Object* obj) {
	writeObject(msg, obj);
	return msg;
}

net::Message& readEmpire(net::Message& msg, Empire** emp) {
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

net::Message& writeEmpire(net::Message& msg, Empire* emp) {
	if(emp)
		msg << emp->id;
	else
		msg << INVALID_EMPIRE;
	return msg;
}

static net::Message& readDesign(net::Message& msg, const Design** dsg) {
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

		unsigned dsgID = msg.readSmall();

		*dsg = emp->getDesign(dsgID, true);
	}
	catch(net::MessageReadError) {
		scripts::throwException("Error reading from message: end of message.");
		return msg;
	}

	return msg;
}

static net::Message& writeDesign(net::Message& msg, const Design** dsg) {
	if(*dsg) {
		if(!(*dsg)->owner) {
			unsigned char empID = 0;
			msg << empID;
			scripts::throwException("Cannot transmit design without owner.");
			return msg;
		}

		msg << (*dsg)->owner->id;
		msg.writeSmall((*dsg)->id);
	}
	else {
		unsigned char empID = 0;
		msg << empID;
	}
	return msg;
}

static bool wrapReadBit(net::Message& msg) {
	try {
		return msg.readBit();
	}
	catch(net::MessageReadError) {
		scripts::throwException("Error reading from message: end of message.");
	}
	return false;
}

static void wrapReadAlign(net::Message& msg) {
	try {
		msg.readAlign();
	}
	catch(net::MessageReadError) {
		scripts::throwException("Error aligning message: end of message.");
	}
}

template<class T>
static net::Message& wrapRead(net::Message& msg, T& value) {
	try {
		msg >> value;
	}
	catch(net::MessageReadError) {
		scripts::throwException("Error reading from message: end of message.");
	}
	return msg;
}

template<class T>
static T wrapExplicitRead(net::Message& msg) {
	T value = T();
	wrapRead<T>(msg, value);
	return value;
}

static unsigned readLimited(net::Message& msg, unsigned limit) {
	try {
		return msg.readLimited(limit);
	}
	catch(net::MessageReadError) {
		scripts::throwException("Error reading from message: end of message.");
	}
	return 0;
}

static void writeLimited(net::Message& msg, unsigned value, unsigned limit) {
	msg.writeLimited(value, limit);
}

static unsigned readSmall(net::Message& msg) {
	try {
		return msg.readSmall();
	}
	catch(net::MessageReadError) {
		scripts::throwException("Error reading from message: end of message.");
	}
	return 0;
}

static void writeSmall(net::Message& msg, unsigned value) {
	msg.writeSmall(value);
}

static int readSignedSmall(net::Message& msg) {
	try {
		return msg.readSignedSmall();
	}
	catch(net::MessageReadError) {
		scripts::throwException("Error reading from message: end of message.");
	}
	return 0;
}

static void writeSignedSmall(net::Message& msg, int value) {
	msg.writeSignedSmall(value);
}

static double readFixed(net::Message& msg, double minimum, double maximum, unsigned bits) {
	try {
		return msg.readFixed(minimum, maximum, bits);
	}
	catch(net::MessageReadError) {
		scripts::throwException("Error reading from message: end of message.");
	}
	return 0.0;
}

static void writeFixed(net::Message& msg, double value, double minimum, double maximum, unsigned bits) {
	msg.writeFixed(value, minimum, maximum, bits);
}

static unsigned readBitValue(net::Message& msg, unsigned bits) {
	try {
		return msg.readBitValue(bits);
	}
	catch(net::MessageReadError) {
		scripts::throwException("Error reading from message: end of message.");
	}
	return 0;
}

static void writeBitValue(net::Message& msg, unsigned value, unsigned bits) {
	msg.writeBitValue(value, bits);
}

static void writeSmallVec3(net::Message& msg, const vec3d& v) {
	msg.writeSmallVec3(v.x, v.y, v.z);
}

static vec3d readSmallVec3(net::Message& msg) {
	vec3d v;
	msg.readSmallVec3(v.x, v.y, v.z);
	return v;
}

static void writeVec3(net::Message& msg, const vec3d& v) {
	msg.writeMedVec3(v.x, v.y, v.z);
}

static vec3d readVec3(net::Message& msg) {
	vec3d v;
	msg.readMedVec3(v.x, v.y, v.z);
	return v;
}

static void writeDir(net::Message& msg, const vec3d& v) {
	msg.writeDirection(v.x, v.y, v.z);
}

static vec3d readDir(net::Message& msg) {
	vec3d v;
	msg.readDirection(v.x, v.y, v.z);
	return v;
}

static void writeRot(net::Message& msg, const quaterniond& v) {
	msg.writeRotation(v.xyz.x, v.xyz.y, v.xyz.z, v.w);
}

static quaterniond readRot(net::Message& msg) {
	quaterniond v;
	msg.readRotation(v.xyz.x, v.xyz.y, v.xyz.z, v.w);
	return v;
}

static void writeLinkMapAll(LinkMap& map, net::Message& msg) {
	auto numPos = msg.reserve<int>();
	int count = 0;

	map.iterateAll([&msg,&count](int64_t key, int64_t value) {
		msg << key;
		msg << value;
		count += 1;
	});

	msg.fill<int>(numPos, count);
}

static void readLinkMap(LinkMap& map, net::Message& msg) {
	int count = 0;;
	msg >> count;

	for(int i = 0; i < count; ++i)
	{
		int64_t key, value;
		msg >> key >> value;
		map.set(key, value);
	}
}

static void writeLinkMapDelta(LinkMap& map, net::Message& msg) {
	auto numPos = msg.reserve<int>();
	int count = 0;

	map.handleDirty([&msg,&count](int64_t key, int64_t value) -> bool {
		msg << key;
		msg << value;
		count += 1;
		return true;
	});

	msg.fill<int>(numPos, count);
}

void RegisterEarlyNetworkBinds(asIScriptEngine* engine) {
	engine->RegisterObjectType("DataList", 0, asOBJ_REF | asOBJ_NOCOUNT);
	engine->RegisterObjectMethod("array<T>", "void syncFrom(DataList@& list)", asFUNCTION(receiveArray), asCALL_CDECL_OBJFIRST);
}

void RegisterNetworkBinds(bool server) {
	InterfaceBind inf("Serializable", false);

	//Message manipulation
	ClassBind msg("Message", asOBJ_VALUE | asOBJ_APP_CLASS_CDA, sizeof(net::Message));
	msg.addConstructor("void f()", asFUNCTION(createMessage));
	msg.addConstructor("void f(const Message&)", asFUNCTION(copyMessage));
	msg.addDestructor("void f()", asFUNCTION(destroyMessage));
	msg.addExternMethod("Message& opAssign(const Message&in)", asFUNCTION(assignMessage));
	msg.addExternMethod("bool get_empty() const", asFUNCTION(emptyMessage));
	msg.addMethod("void dump() const", asMETHOD(net::Message, dump));
	msg.addMethod("uint get_size() const", asMETHOD(net::Message, size));
	msg.addMethod("bool get_error() const", asMETHOD(net::Message, hasError))
		doc("Returns true if there was an error during a read operation.", "");

	msg.addExternMethod("uint reserve()", asFUNCTION(reserveInt));
	msg.addExternMethod("void fill(uint, int)", asFUNCTION(fillInt));

	msg.addMethod("void writeBit(bool)", asMETHOD(net::Message, writeBit));
	msg.addMethod("void write1()", asMETHOD(net::Message, write1));
	msg.addMethod("void write0()", asMETHOD(net::Message, write0));
	msg.addExternMethod("bool readBit()", asFUNCTION(wrapReadBit));

	msg.addMethod("void writeAlign()", asMETHOD(net::Message, writeAlign));
	msg.addExternMethod("void readAlign()", asFUNCTION(wrapReadAlign));

	msg.addExternMethod("void dumpWritePosition()", asFUNCTION(msgDumpWrite));
	msg.addExternMethod("void dumpReadPosition()", asFUNCTION(msgDumpRead));

	msg.addExternMethod("void writeSmall(uint value)", asFUNCTION(writeSmall));
	msg.addExternMethod("uint readSmall()", asFUNCTION(readSmall));

	msg.addExternMethod("void writeSignedSmall(int value)", asFUNCTION(writeSignedSmall));
	msg.addExternMethod("int readSignedSmall()", asFUNCTION(readSignedSmall));

	msg.addExternMethod("void writeLimited(uint value, uint limit)", asFUNCTION(writeLimited));
	msg.addExternMethod("uint readLimited(uint limit)", asFUNCTION(readLimited));

	msg.addExternMethod("void writeBitValue(uint value, uint bits)", asFUNCTION(writeBitValue));
	msg.addExternMethod("uint readBitValue(uint bits)", asFUNCTION(readBitValue));
	
	msg.addExternMethod("void writeFixed(double value, double minimum = 0.0, double maximum = 1.0, uint bits = 16)", asFUNCTION(writeFixed))
		doc("Writes a double that is guaranteed to fall into the rage [minimum,maximum) using a specified number of bits.", "", "", "", "", "");
	msg.addExternMethod("double readFixed(double minimum = 0.0, double maximum = 1.0, uint bits = 16)", asFUNCTION(readFixed));
	
	msg.addExternMethod("void writeSmallVec3(const vec3d& v)", asFUNCTION(writeSmallVec3))
		doc("Writes a compressed vec3d into a very small space, sacrificing minimal quality.", "");
	msg.addExternMethod("vec3d readSmallVec3()", asFUNCTION(readSmallVec3));
	
	msg.addExternMethod("void writeMedVec3(const vec3d& v)", asFUNCTION(writeVec3))
		doc("Writes a compressed vec3d into a smaller space, sacrificing very little quality.", "");
	msg.addExternMethod("vec3d readMedVec3()", asFUNCTION(readVec3));
	
	msg.addExternMethod("void writeDirection(const vec3d& v)", asFUNCTION(writeDir))
		doc("Writes a unit vector in a much smaller size.", "");
	msg.addExternMethod("vec3d readDirection()", asFUNCTION(readDir));
	
	msg.addExternMethod("void writeRotation(const quaterniond& v)", asFUNCTION(writeRot))
		doc("Writes a rotation (unit quaternion) in a much smaller size.", "");
	msg.addExternMethod("quaterniond readRotation()", asFUNCTION(readRot));

	msg.addExternMethod("Message& opShl(Serializable@)", asFUNCTION(writeSerial));
	msg.addExternMethod("Message& opShr(Serializable@)", asFUNCTION(readSerial));

	msg.addMethod("Message& opShl(bool)",
		asMETHODPR(net::Message, operator<<, (bool), net::Message&));

	msg.addExternMethod("Message& opShr(bool&)",
		asFUNCTION(wrapRead<bool>));

#define BIND_TYPE_SHONLY(stype, rtype)\
	msg.addMethod("Message& opShl(" #stype "&)",\
		asMETHODPR(net::Message, operator<<, (const rtype&), net::Message&));\
\
	msg.addExternMethod("Message& opShr(" #stype "&)",\
		asFUNCTION(wrapRead<rtype>));

#define BIND_TYPE(stype, rtype)\
	BIND_TYPE_SHONLY(stype, rtype)\
\
	msg.addExternMethod(#stype " read_" #stype "()",\
		asFUNCTION(wrapExplicitRead<rtype>));

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
	BIND_TYPE_SHONLY(locked_int, int);
	BIND_TYPE_SHONLY(locked_double, double);

	msg.addExternMethod("Message& opShl(ElevationMap&)", asFUNCTION(writeElevation));
	msg.addExternMethod("Message& opShr(ElevationMap&)", asFUNCTION(readElevation));

	msg.addExternMethod("Message& opShl(Object@+)", asFUNCTION(writeObjectScr));
	msg.addExternMethod("Message& opShr(Object@&)", asFUNCTION(readObjectScr));
	msg.addExternMethod("Object@ readObject()", asFUNCTION(readObject_e));

	msg.addExternMethod("Message& opShl(Empire@)", asFUNCTION(writeEmpire));
	msg.addExternMethod("Message& opShr(Empire@&)", asFUNCTION(readEmpire));

	msg.addExternMethod("Message& opShl(const Design@&)", asFUNCTION(writeDesign));
	msg.addExternMethod("Message& opShr(const Design@&)", asFUNCTION(readDesign));

	//Serializable interface
	inf.addMethod("void read(Message& msg)");
	inf.addMethod("void write(Message& msg)");

	//DataList and yield stuff
	bind("bool receive(DataList@& list, Serializable@ obj)", asFUNCTION(receive));
	bind("bool receive(DataList@& list, Object@& obj)", asFUNCTION(receiveObject));
	bind("void yield(const Serializable& obj)", asFUNCTION(yield));
	bind("void yield(const Object& obj)", asFUNCTION(yieldObject));
	bind("Message& startYield()", asFUNCTION(getYieldMessage));
	bind("void finishYield()", asFUNCTION(finalizeYield));
	bind("void setNickname(const string& nick)", asFUNCTION(setNickname));

	//Keep function pointers
	asITypeInfo* type = getEngine()->GetTypeInfoByName("Serializable");

	if(type) {
		asIScriptEngine* engine = getEngine();
		engine->SetUserData(type, EDID_SerializableType);
		engine->SetUserData(type->GetMethodByDecl("void write(Message& msg)"), EDID_SerializableWrite);
		engine->SetUserData(type->GetMethodByDecl("void read(Message& msg)"), EDID_SerializableRead);
	}
	else {
		error("ERROR: Problem registering Serializable type interface.");
	}

	{
		ClassBind linkMap("LinkMap");
		linkMap.addExternMethod("void writeAll(Message& msg)", asFUNCTION(writeLinkMapAll));
		linkMap.addExternMethod("void writeDirty(Message& msg)", asFUNCTION(writeLinkMapDelta));
		linkMap.addExternMethod("void readAll(Message& msg)", asFUNCTION(readLinkMap));
		linkMap.addExternMethod("void readDirty(Message& msg)", asFUNCTION(readLinkMap));
	}
}

};
