#ifdef _MSC_VER
#include <Windows.h>
#endif

#include "binds.h"
#include "constants.h"
#include "str_util.h"
#include "obj/object.h"
#include "util/random.h"
#include "scripts/context_cache.h"
#include "../source/as_scriptengine.h"
#include "../source/as_scriptobject.h"
#include "../../as_addons/include/scriptarray.h"
#include "main/initialization.h"
#include "main/references.h"
#include "main/logging.h"
#include "main/tick.h"
#include "main/version.h"
#include "main/game_platform.h"
#include "util/format.h"
#include "files.h"
#include <algorithm>
#include "main/console.h"
#include "network/network_manager.h"
#include <string>
#include <limits.h>
#include <limits>

#ifdef __GNUC__
#include <unistd.h>
#endif

extern unsigned reportVersion;
extern bool isLoadedGame, gameEnding;
extern int SAVE_VERSION, START_VERSION;
int FindCubicRoots(const double coeff[4], double x[3]);
int FindQuarticRoots(const double coeff[5], double x[4]);

const bool _TRUE = true;
const bool _FALSE = false;

const int _INT_MAX = INT_MAX;
const int _INT_MIN = INT_MIN;
const unsigned _UINT_MAX = UINT_MAX;
const float _F_INFINITY = std::numeric_limits<float>::infinity();
const double _D_INFINITY = std::numeric_limits<double>::infinity();
const std::string _BUILD_NAME(BUILD_VERSION);
#ifdef NSTEAM
const bool isSteamBuild = false;
#else
const bool isSteamBuild = true;
#endif

extern double frameTime_s;

namespace scripts {

double getExactTime() {
	return devices.driver->getAccurateTime();
}

double getGameTime() {
	return devices.driver->getGameTime();
}

double getFrameGameTime() {
	return frameTime_s;
}

double getFrameTime() {
	return devices.driver->getFrameTime();
}

double getFrameLength() {
	return realFrameLen;
}

unsigned getBasicTime() {
	return unsigned(devices.driver->getTime());
}

double getGameSpeed() {
	return devices.driver->getGameSpeed();
}

void setGameSpeed(double speed) {
	if(devices.network->isClient) {
		scripts::throwException("Cannot set game speed on client.");
		return;
	}
	if(devices.network->isServer) {
		if(devices.network->isSerializing())
			return;
		devices.network->setGameSpeed(speed);
	}
	return devices.driver->setGameSpeed(speed);
}

static bool mpClient() {
	return devices.network->isClient;
}

static bool mpServer() {
	return devices.network->isServer;
}

static bool isTestScripts() {
	return game_state == GS_Test_Scripts;
}

static bool isModdedGame() {
	if(devices.mods.activeMods.size() == 0)
		return true;
	return devices.mods.activeMods.size() > 1 || devices.mods.activeMods[0] != devices.mods.getMod("base");
}

static unsigned mpGalaxiesInFlight() {
	return devices.network->galaxiesInFlight;
}

static bool mpIsSerializing() {
	return devices.network->isSerializing();
}

static void mpConnect(const std::string& address, int port, const std::string& password) {
	devices.network->connect(address, port, password, true);
}

static void mpDisconnect() {
	devices.network->disconnect();
	devices.network->resetNetState();
}

static bool mpIsConnected() {
	return devices.network->isClient && devices.network->connected;
}

static bool mpIsConnecting() {
	return devices.network->isClient && devices.network->client && !devices.network->connected;
}

static void mpSetPassword(const std::string& pwd) {
	devices.network->setPassword(pwd);
}

template<class T>
T sqr(T x) {
	return x*x;
}
static std::string localize(const std::string& str, bool requireHash, bool doUnescape) {
	return devices.locale.localize(str, requireHash, doUnescape);
}

static std::string getStackTrace(bool verbose) {
	return getStackTrace(asGetActiveContext(), verbose);
}

static void logExc(bool verbose) {
	auto* ctx = asGetActiveContext();
	if(ctx) {
		error("Script Exception: %s", ctx->GetExceptionString());
		error(getStackTrace(asGetActiveContext(), verbose));
	}
}

static bool scriptFuncSplit(const std::string& input, std::string* name, CScriptArray* arguments, bool strip) {
	std::vector<std::string> args;
	if(!funcSplit(input, *name, args, strip))
		return false;

	arguments->Resize(args.size());
	for(unsigned i = 0, cnt = args.size(); i < cnt; ++i)
		*(std::string*)arguments->At(i) = args[i];
	return true;
}

#define a(n) const std::string& a##n
#define v(n) a##n

std::string format_1(const std::string& text, a(1)) {
	return format(text.c_str(), v(1));
}

std::string format_2(const std::string& text, a(1), a(2)) {
	return format(text.c_str(), v(1), v(2));
}

std::string format_3(const std::string& text, a(1), a(2), a(3)) {
	return format(text.c_str(), v(1), v(2), v(3));
}

std::string format_4(const std::string& text, a(1), a(2), a(3), a(4)) {
	return format(text.c_str(), v(1), v(2), v(3), v(4));
}

std::string format_5(const std::string& text, a(1), a(2), a(3), a(4), a(5)) {
	return format(text.c_str(), v(1), v(2), v(3), v(4), v(5));
}

std::string format_n(const std::string& text, CScriptArray* arguments) {
	FormatArg argbuf[32];
	unsigned argn = arguments->GetSize();
	for(unsigned i = 0; i < argn && i < 32; ++i)
		argbuf[i] = FormatArg(*(const std::string*)arguments->At(i));

	std::string output;
	format(output, text.c_str(), argn, argbuf);
	return output;
}

template<class T>
T absceil(T a) {
	return a > 0 ? ceil(a) : floor(a);
}

template<class T>
T absfloor(T a) {
	return a > 0 ? floor(a) : ceil(a);
}

template<class T>
T scr_max(T a, T b) {
	return a < b ? b : a;
}

template<class T, class S>
T scr_mix_max(T a, S b) {
	return a < (T)b ? (T)b : a;
}

template<class T>
T scr_min(T a, T b) {
	return b < a ? b : a;
}

template<class T, class S>
T scr_mix_min(T a, S b) {
	return (T)b < a ? (T)b : a;
}

template<class T>
T clamp(T val, T _min, T _max) {
	if(val < _min)
		return _min;
	if(val > _max)
		return _max;
	return val;
}

void QuarticRoots(double a, double b, double c, double d, double e, CScriptArray& out) {
	double coeffs[5] = {e,d,c,b,a};
	double roots[4];
	int rootCount = FindQuarticRoots(coeffs, roots);
	out.Resize((asUINT)rootCount);
	for(int i = 0; i < rootCount; ++i)
		*(double*)out.At(i) = roots[i];
}

const double straightDot = 0.99999;

//Special case of quadratic root solution for newtonian motion
double lowerQuadratic(double a, double b, double c) {
	double det = b*b - 4.0*a*c;
	if(det < 0.0)
		return 1000.0;
	double d = sqrt(det);
	double r = (-b - d) / (2.0 * a);
	if(r > 0.0)
		return r;
	else
		return 1000.0;
}

double newtonArrivalTime(double a, const vec3d& p, const vec3d& v) {
	if(a < 1.0e-4 || a != a)
		a = 1.0e-4;
	double dist = p.getLength();
	double speed = v.getLengthSQ();
	if(speed < 0.004)
		return sqrt(4.0 * dist / a);
	speed = sqrt(speed);

	double velDot = 1.0;
	if(dist > 0.001)
		velDot = v.dot(p) / (dist * speed);

	if(velDot > straightDot) {
		//We must accelerate up to the target speed before hitting the point
		
		// d = 1/2 a * t^2 (where t = v/a)
		double accelDist = 0.5 * speed * speed / a;
		
		if(accelDist > dist) {
			return lowerQuadratic(-a, 2.0 * speed, dist - accelDist);
		}
		else {
			//We have enough distance
			//Accelerate until we must decelerate
			double totalTime = sqrt(4.0 * (dist - accelDist) / a);
			return totalTime + (speed / a);
		}
	}
	else if(velDot < -straightDot) {
		double deccelTime = speed / a;
		double deccelDist = deccelTime * speed * 0.5;
		
		//We either need to slow down, or accelerate to a maximum velocity
		if(deccelDist < dist) {
			double totalTime = sqrt(4.0 * (deccelDist + dist) / a);
			return totalTime - (speed / a);
		}
		else {
			return deccelTime + sqrt(4.0 * (deccelDist - dist) / a);
		}
	}
	else {
		vec3d linearVel = p.normalized(speed * velDot);
		vec3d latVel = v - linearVel;
		vec3d zero;
		
		double aToward = 0.7;
		
		double rangeLow = 0.0001, rangeHigh = 0.9999;
		double t = 0, leastErr = 99999999.0;
		for(unsigned i = 0; i < 15; ++i) {
			double aLat = sqrt(1.0 - (aToward * aToward));
		
			double tToward = newtonArrivalTime(aToward * a, p, linearVel);
			double tLat = newtonArrivalTime(aLat * a, zero, latVel);
				
			double err = abs(tToward - tLat);
			if(err < leastErr) {
				leastErr = err;
				t = (tToward + tLat) * 0.5;
			}
			
			if(err < 0.02)
				break;
			else if(tToward > tLat) {
				rangeLow = aToward;
				aToward = (rangeLow + rangeHigh) * 0.5;
			}
			else {
				rangeHigh = aToward;
				aToward = (rangeLow + rangeHigh) * 0.5;
			}
		}
		
		return t;
	}
}

void throwScriptError(const std::string& str) {
	scripts::throwException(str.c_str());
}

void _print(bool v) {
	if(v)
		print("true");
	else
		print("false");
}

void _print(int v) {
	std::string str =toString<int>(v);
	print(str);
}

void _print(unsigned v) {
	std::string str =toString<unsigned>(v);
	print(str);
}

void _print(float v) {
	std::string str =toString<float>(v);
	print(str);
}

void _print(double v) {
	std::string str =toString<double>(v);
	print(str);
}

void _print() {
	//Does nothing
}

void _print(void* ptr, int typeId) {
	auto* eng = asGetActiveContext()->GetEngine();
	auto* type = eng->GetTypeInfoById(typeId);

	if(ptr != nullptr && (typeId & asTYPEID_SCRIPTOBJECT))
		type = ((asIScriptObject*)ptr)->GetObjectType();
	print("%s at %p", type->GetName(), ptr);
}

std::string strPointer(void* ptr, int typeId) {
	auto* eng = asGetActiveContext()->GetEngine();
	auto* type = eng->GetTypeInfoById(typeId);
	if(ptr != nullptr && (typeId & asTYPEID_SCRIPTOBJECT))
		type = ((asIScriptObject*)ptr)->GetObjectType();

	std::stringstream ss;
	ss << '[';
	ss << type->GetName();
	ss << " at 0x";
	ss << std::hex << (size_t)ptr;
	ss << ']';

	return ss.str();
}

std::string dbgStr(void* ptr, int typeId) {
	auto* eng = asGetActiveContext()->GetEngine();
	return getScriptVariable(ptr, typeId, true, eng);
}

void dbgOut(void* ptr, int typeId, const std::string& prefix) {
	auto* eng = asGetActiveContext()->GetEngine();
	std::string err;
	if(!prefix.empty()) {
		err += prefix;
		err += " ";
	}
	err += eng->GetTypeDeclaration(typeId);
	err += " ";
	err += getScriptVariable(ptr, typeId, true, eng);
	error(err);
}

void dbgAll(const std::string& prefix) {
	if(!prefix.empty()) {
		error( "########################################");
		error(prefix);
	}
	error(getStackVariables(asGetActiveContext()));
	if(!prefix.empty()) {
		error( "########################################");
	}
}

int getRefCnt(void* ptr, int typeId) {
	if(ptr != nullptr && (typeId & asTYPEID_SCRIPTOBJECT))
		return (int)((asCScriptObject*)ptr)->GetRefCount();
	return -1;
}

long long dbgAddress(void* ptr, int typeId) {
	return (long long)ptr;
}

#ifdef WIN_MODE
bool isWindows = true;
#else
bool isWindows = false;
#endif
#ifdef LIN_MODE
bool isLinux = true;
#else
bool isLinux = false;
#endif
#ifdef MAC_MODE
bool isMac = true;
#else
bool isMac = false;
#endif

static std::string archName = ARCH_NAME;
static unsigned archBits = ARCH_BITS;

template<class T>
static T wrap_toNumber(const std::string& str) {
	return toNumber<T>(str);
}

static bool wrap_toBool(const std::string& str) {
	return toBool(str);
}

static vec3d toVec3d(const std::string& str) {
	vec3d v;
	int count = sscanf(str.c_str(), " ( %lf , %lf , %lf", &v.x, &v.y, &v.z);
	if(count == 3)
		return v;
	else
		return vec3d();
}

static void addConsComm(std::string& name, asIScriptObject* obj) {
	Manager* man = getActiveManager();
	asIScriptFunction* conCommandFunc = (asIScriptFunction*)man->engine->GetUserData(EDID_consoleCommand);

	if(!obj || !conCommandFunc) {
		throwException("Unbound function called.");
		return;
	}

	obj->AddRef();

	Console::ConsoleFunction f;
	f.line = [obj,man,conCommandFunc](std::string& line) -> bool {
		Call cl = man->call(conCommandFunc);
		cl.setObject(obj);
		cl.push(&line);
		cl.call();
		return true;
	};

	f.destruct = [obj]() -> bool {
		obj->Release();
		return true;
	};

	console.addCommand(name, f);
}

static bool strIsWhitespace(const std::string& str, const std::string& substr) {
	return str.find_first_not_of(" \t\n\r") == std::string::npos;
}

static bool strContains(const std::string& str, const std::string& substr) {
	return str.find(substr) != std::string::npos;
}

static bool strContainsNC(const std::string& str, const std::string& substr) {
	return strfind_nocase(str, substr) != -1;
}

static bool startsWith(const std::string& str, const std::string& substr) {
	if(substr.size() > str.size())
		return false;
	return str.compare(0, substr.size(), substr) == 0;
}

static bool endsWith(const std::string& str, const std::string& substr) {
	if(substr.size() > str.size())
		return false;
	return str.compare(str.size() - substr.size(), substr.size(), substr) == 0;
}

static bool startsWithNC(const std::string& str, const std::string& substr) {
	return streq_nocase(str, substr, 0, substr.size());
}

static bool endsWithNC(const std::string& str, const std::string& substr) {
	return streq_nocase(str, substr, str.size() - substr.size(), substr.size());
}

static bool strEq_s(const std::string& str, const std::string& substr, int index) {
	if(substr.size() > str.size())
		return false;
	return str.compare(index, substr.size(), substr) == 0;
}

static bool strEq_sl(const std::string& str, const std::string& substr, int index, int length) {
	if(substr.size() > str.size())
		return false;
	return str.compare(index, length, substr) == 0;
}

static bool strEqNC_s(const std::string& str, const std::string& substr, int index) {
	return streq_nocase(str, substr, index);
}

static bool strEqNC_sl(const std::string& str, const std::string& substr, int index, int length) {
	return streq_nocase(str, substr, index, length);
}

static std::string getCurModule() {
	auto* ctx = asGetActiveContext();
	auto* func = ctx->GetFunction(ctx->GetCallstackSize() - 1);
	return std::string(func->GetModuleName());
}

void copyToClipboard(const std::string& str) {
	devices.driver->setClipboard(str);
}

std::string readFromClipboard() {
	return devices.driver->getClipboard();
}

static void toggleConsole() {
	console.toggle();
}

static double angleDiff(double a, double b) {
	double diff = a - b;
	if(diff < -pi) {
		do {
			diff += twopi;
		} while(diff < -pi);
	}
	else if(diff > pi) {
		do {
			diff -= twopi;
		} while(diff > pi);
	}
	
	return diff;
}

static bool isCloudActive() {
	return devices.cloud != nullptr;
}

static void inviteCloudFriend() {
	if(devices.cloud)
		devices.cloud->inviteFriend();
}

static std::string getCloudNickname() {
	if(devices.cloud == nullptr)
		return "";
	return devices.cloud->getNickname();
}

static bool inCloudLobby() {
	if(devices.cloud == nullptr)
		return false;
	return devices.cloud->getLobby() != 0;
}

static void enterCloudQueue(const std::string& type, unsigned players, const std::string& version) {
	if(devices.cloud == nullptr)
		return;
	devices.cloud->enterQueue(type, players, version);
}

static bool cloudQueueReady() {
	if(devices.cloud == nullptr)
		return false;
	return devices.cloud->queueReady();
}

static bool cloudQueueRequest() {
	if(devices.cloud == nullptr)
		return false;
	return devices.cloud->queueRequest();
}

static void cloudQLeave() {
	if(devices.cloud)
		devices.cloud->leaveQueue();
}

static void cloudQAccept() {
	if(devices.cloud)
		devices.cloud->acceptQueue();
}

static void cloudQReject() {
	if(devices.cloud)
		devices.cloud->rejectQueue();
}

static double cloudQTime() {
	if(devices.cloud == nullptr)
		return 0;
	return (double)devices.cloud->remainingTime() / 1000.0;
}

static unsigned cloudQPlayers() {
	if(devices.cloud == nullptr)
		return 0;
	return devices.cloud->queueTotalPlayers();
}

static bool cloudInQ() {
	if(devices.cloud == nullptr)
		return false;
	return devices.cloud->inQueue();
}

static bool cloudQWaiting(unsigned& ready, unsigned& cap) {
	ready = 0;
	cap = 0;

	if(devices.cloud == nullptr)
		return false;
	return devices.cloud->queuePlayerWait(ready, cap);
}

void cloudCreateItem(const std::string& folder) {
	if(!devices.cloud) return;
	if(!isAccessible(folder)) return;
	devices.cloud->createCloudItem(folder);
}

void cloudCloseItem() {
	if(devices.cloud) devices.cloud->closeItem();
}

bool cloudItemReady() {
	if(!devices.cloud)
		return false;
	return devices.cloud->isItemActive();
}

unsigned long long cloudItemID() {
	if(!devices.cloud)
		return 0;
	return devices.cloud->getItemID();
}

void cloudItemTitle(const std::string& title) {
	if(!devices.cloud) return;
	devices.cloud->setItemTitle(title);
}

void cloudItemDesc(const std::string& desc) {
	if(!devices.cloud) return;
	devices.cloud->setItemDescription(desc);
}

void cloudItemFolder(const std::string& folder) {
	if(!devices.cloud) return;
	if(!isAccessible(folder)) return;
	devices.cloud->setItemContents(folder);
}

void cloudItemImage(const std::string& image) {
	if(!devices.cloud) return;
	if(!isAccessible(image)) return;

	devices.cloud->setItemImage(devices.mods.resolve(image));
}

void cloudItemTags(CScriptArray& sTags) {
	if(!devices.cloud) return;

	std::vector<std::string> tags;
	tags.reserve(sTags.GetSize());
	for(unsigned i = 0; i < sTags.GetSize(); ++i)
		tags.push_back(*(std::string*)sTags.At(i));

	devices.cloud->setItemTags(tags);
}

void cloudItemVisible() {
	if(!devices.cloud) return;
	devices.cloud->setItemVisibility();
}

void cloudItemCommit(const std::string& log) {
	if(!devices.cloud) return;
	devices.cloud->commitItem(log);
}

double cloudItemProgress() {
	if(!devices.cloud)
		return 0;
	return devices.cloud->getUploadProgress();
}

bool cloudItemUploading() {
	if(!devices.cloud)
		return false;
	return devices.cloud->isItemUpdating();
}

void cloudLegal() {
	if(devices.cloud) devices.cloud->openURL("http://steamcommunity.com/sharedfiles/workshoplegalagreement");
}

#ifdef _MSC_VER
threads::threadreturn threadcall openURL(void* arg) {
	std::string* pStr = (std::string*)arg;
	ShellExecute(NULL, "open", pStr->c_str(), NULL, NULL, SW_SHOW);
	delete pStr;
	return 0;
}
#endif

static void openBrowser(const std::string& url) {
	if(!startsWithNC(url, "http://") && !startsWithNC(url, "https://"))
		return;
	if(devices.cloud) {
		devices.cloud->openURL(url);
		return;
	}
#ifdef __GNUC__
	if(fork() == 0) {
		execlp("xdg-open", "xdg-open", url.c_str(), (char*)nullptr);
		exit(1);
	}
#else
	threads::createThread(openURL, new std::string(url));
#endif
}

static void openFileManager(const std::string& folder) {
	if(!isDirectory(folder) || !isAccessible(folder))
		return;
#ifdef __GNUC__
	if(fork() == 0) {
		execlp("xdg-open", "xdg-open", folder.c_str(), (char*)nullptr);
		exit(1);
	}
#else
	threads::async([folder]() -> int {
		ShellExecute(NULL, "explore", folder.c_str(), NULL, NULL, SW_SHOWNORMAL);
		return 0;
	});
#endif
}

#ifdef _DEBUG
static void scrAssert(void* ptr, int tid) {
	assert(false);
}
#endif

static void dumpGC() {
	auto* ctx = asGetActiveContext();
	auto* eng = (asCScriptEngine*)ctx->GetEngine();

	ENTERCRITICALSECTION(eng->gc.gcCritical);
	for(unsigned i = 0, cnt = eng->gc.gcOldObjects.GetLength(); i < cnt; ++i) {
		auto* type = eng->gc.gcOldObjects[i].type;
		auto* mod = type->GetModule();
		if(mod)
			print("%s::%s", type->GetModule()->GetName(), type->GetName());
		else
			print("::%s", type->GetName());
	}
	for(unsigned i = 0, cnt = eng->gc.gcNewObjects.GetLength(); i < cnt; ++i) {
		auto* type = eng->gc.gcNewObjects[i].type;
		auto* mod = type->GetModule();
		if(mod)
			print("%s::%s", type->GetModule()->GetName(), type->GetName());
		else
			print("::%s", type->GetName());
	}
	LEAVECRITICALSECTION(eng->gc.gcCritical);
}

void RegisterGeneralBinds(bool server, bool shadow) {
	//Debugging functions
	bind("void print(const string &)", asFUNCTIONPR(print,(const std::string&),void));
	bind("void info(const string &)", asFUNCTIONPR(info,(const std::string&),void));
	bind("void warn(const string &)", asFUNCTIONPR(warn,(const std::string&),void));
	bind("void error(const string &)", asFUNCTIONPR(error,(const std::string&),void));
	bind("void throw(const string &)", asFUNCTION(throwScriptError));

	bind("void dumpGC()", asFUNCTION(dumpGC));

	bind("string getStackTrace(bool verbose = false)", asFUNCTIONPR(getStackTrace, (bool), std::string));
	bind("string get___module__()", asFUNCTION(getCurModule));

	bind("void openBrowser(const string& url)", asFUNCTION(openBrowser))
		doc("Open a URI in the user's configured browser.", "URI to open.");
	bind("void openFileManager(const string& folder)", asFUNCTION(openFileManager))
		doc("Open a folder in the user's configured file manager.", "Folder to open.");

	bindGlobal("uint errorVersion", &reportVersion)
		doc("Value reported to Steam when an exception occurs.");

	bind("bool hasDLC(const string& name)", asFUNCTION(hasDLC));

#ifdef _DEBUG
	//Use temporarily while debugging to break from scripts
	bind("void __break(?&)", asFUNCTION(scrAssert));
#endif

	//Bind all the locales
	{
		Namespace ns("locale");

		foreach(it, devices.locale.localizations)
			bindGlobal(format("::string $1", it->first).c_str(), it->second);
	}

	//Platform detection
	bindGlobal("bool isWindows", &isWindows);
	bindGlobal("bool isLinux", &isLinux);
	bindGlobal("bool isMac", &isMac);
	bindGlobal("uint ArchBits", &archBits);
	bindGlobal("string ArchName", &archName);

	//Global game state
	bindGlobal("bool isLoadedSave", &isLoadedGame);
	bindGlobal("int SAVE_VERSION", &SAVE_VERSION);
	bindGlobal("int START_VERSION", &START_VERSION);
	bindGlobal("bool game_running", &game_running);
	bindGlobal("bool game_ending", &gameEnding)
		doc("True while the game is being cleaned up for exit.");
	bindGlobal("bool inGalaxyCreation", &Object::GALAXY_CREATION);

	//Maximums
	bindGlobal("int INT_MAX", (void*)&_INT_MAX);
	bindGlobal("int INT_MIN", (void*)&_INT_MIN);
	bindGlobal("uint UINT_MAX", (void*)&_UINT_MAX);
	bindGlobal("double INFINITY", (void*)&_D_INFINITY);
	bindGlobal("float FLOAT_INFINITY", (void*)&_F_INFINITY);
	bindGlobal("const string BUILD_VERSION", (void*)&_BUILD_NAME);
	bindGlobal("const bool IS_STEAM_BUILD", (void*)&isSteamBuild);

	//Engine detection
	if(server) {
		bindGlobal("bool isServer", (void*)&_TRUE);
		bindGlobal("bool isClient", (void*)&_FALSE);
	}
	else {
		bindGlobal("bool isServer", (void*)&_FALSE);
		bindGlobal("bool isClient", (void*)&_TRUE);
	}

	if(shadow)
		bindGlobal("bool isShadow", (void*)&_TRUE);
	else
		bindGlobal("bool isShadow", (void*)&_FALSE);

	//Networking detection
	bind("bool get_mpClient()", asFUNCTION(mpClient));
	bind("bool get_mpServer()", asFUNCTION(mpServer));
	bind("uint get_mpGalaxiesInFlight()", asFUNCTION(mpGalaxiesInFlight));
	bind("bool get_mpIsSerializing()", asFUNCTION(mpIsSerializing));
	bind("bool get_isScriptDebug()", asFUNCTION(isTestScripts));
	bind("bool get_isModdedGame()", asFUNCTION(isModdedGame));

	if(!server && !shadow) {
		bind("void mpConnect(const string& address, int port = 2048, const string& password = \"\")", asFUNCTION(mpConnect));
		bind("void mpDisconnect()", asFUNCTION(mpDisconnect));
		bind("bool mpIsConnected()", asFUNCTION(mpIsConnected));
		bind("bool mpIsConnecting()", asFUNCTION(mpIsConnecting));
		bind("void mpSetPassword(const string& str)", asFUNCTION(mpSetPassword));
	}
	
	//Timing functions
	bind("double getExactTime()", asFUNCTION(getExactTime))
		doc("Returns nanosecond-accurate system time in seconds (slow).", "");

	bind("double get_gameTime()", asFUNCTION(getGameTime))
		doc("Returns the current game clock, updated periodically, in seconds.", "");
	bind("double get_frameGameTime()", asFUNCTION(getFrameGameTime))
		doc("Returns the current frame's game time, updated every frame, in seconds.", "");
	bind("double get_frameTime()", asFUNCTION(getFrameTime))
		doc("Returns the current frame time in seconds.", "");
	bind("double get_frameLength()", asFUNCTION(getFrameLength))
		doc("Returns the timespan represented by this frame in seconds.", "");
	bind("uint get_systemTime()", asFUNCTION(getBasicTime))
		doc("Returns millisecond-accurate system time in milliseconds.", "");

	bind("double get_gameSpeed()", asFUNCTION(getGameSpeed));
	bind("void set_gameSpeed(double speed)", asFUNCTION(setGameSpeed));

	//Randomness
	bind("double randomd()", asFUNCTIONPR(randomd, (), double))
		doc("Generate a random double value.", "Random value from [0.0,1.0).");

	bind("double randomd(double min, double max)", asFUNCTIONPR(randomd, (double, double), double))
		doc("Generate a random double value.", "Minimum return.", "Maximum return (non-inclusive).", "Random value from [min,max).");

	bind("float randomf()", asFUNCTIONPR(randomf, (), float))
		doc("Generate a random float value.", "Random value from [0.f,1.f).");

	bind("float randomf(float min, float max)", asFUNCTIONPR(randomf, (float, float), float))
		doc("Generate a random float value.", "Minimum return.", "Maximum return (non-inclusive).", "Random value from [min,max).");

	bind("uint randomi()", asFUNCTIONPR(randomi, (), unsigned))
		doc("Generate a random uint value.", "Random value from 0 to UINT_MAX, inclusive.");
	bind("int randomi(int min, int max)", asFUNCTIONPR(randomi, (int, int), int))
		doc("Generate a random int value.", "Minimum return.", "Maximum return  (inclusive).", "Random value from min to max, inclusive.");
	
	bind("uint sysRandomi()", asFUNCTION(sysRandomi))
		doc("Attempts to generate a high-quality random number. May fall back to a weaker random generation. Slow.", "");

	bind("double normald(double min, double max, int steps = 3)", asFUNCTION(normald))
		doc("Generates an approximately normally distributed value within a range, within an average return at the mean of min and max.", "Minimum return", "Maximum return (non-inclusive)", "Number of steps to iterate (more is a tighter distribution)", "Random value from [min,max)");

	bind("vec3d random3d(double radius = 1.0)", asFUNCTIONPR(random3d, (double), vec3d))
		doc("Generates a random 3D rotation, uniformly distributed over a sphere surface.",
				"Radius of sphere.", "Random rotation vector.");

	bind("vec2d random2d(double radius = 1.0)", asFUNCTIONPR(random2d, (double), vec2d))
		doc("Generates a random 2D rotation, uniformly distributed over a circle's circumference.",
				"Radius of circle.", "Random rotation vector.");

	bind("vec3d random3d(double minRadius, double maxRadius)", asFUNCTIONPR(random3d, (double, double), vec3d))
		doc("Generates a random 3D rotation, distributed evenly on the volume between minRadius and maxRadius.",
				"Minimum radius of the vector.", "Maximum radius of the vector.", "Random rotation vector.");

	bind("vec2d random2d(double minRadius, double maxRadius)", asFUNCTIONPR(random2d, (double, double), vec2d))
		doc("Generates a random 2D rotation, distributed evenly on the area between minRadius and maxRadius.",
				"Minimum radius of the vector.", "Maximum radius of the vector.", "Random rotation vector.");

	//Math
	bind("double sqr(double)", asFUNCTION(sqr<double>));
	bind("float sqr(float)", asFUNCTION(sqr<float>));
	bind("int sqr(int)", asFUNCTION(sqr<int>));

	bind("double max(double, double)", asFUNCTION(scr_max<double>));
	bind("int max(int, int)", asFUNCTION(scr_max<int>));
	bind("uint max(uint, uint)", asFUNCTION(scr_max<unsigned>));
	bind("uint max(uint, int)", asFUNCTION((scr_mix_max<unsigned,int>)));
	bind("int max(int, uint)", asFUNCTION((scr_mix_max<int,unsigned>)));

	bind("double min(double, double)", asFUNCTION(scr_min<double>));
	bind("int min(int, int)", asFUNCTION(scr_min<int>));
	bind("uint min(uint, uint)", asFUNCTION(scr_min<unsigned>));
	bind("uint min(uint, int)", asFUNCTION((scr_mix_min<unsigned,int>)));
	bind("int min(int, uint)", asFUNCTION((scr_mix_min<int,unsigned>)));

	bind("double clamp(double value, double minimum, double maximum)", asFUNCTION(clamp<double>))
		doc("Clamps the value to within the specified range.", "", "", "", "");
	bind("int clamp(int value, int minimum, int maximum)", asFUNCTION(clamp<int>))
		doc("Clamps the value to within the specified range.", "", "", "", "");

	bind("int abs(int)", asFUNCTIONPR(abs, (int), int));

	bind("double absceil(double)", asFUNCTION(absceil<double>));
	bind("float absceil(float)", asFUNCTION(absceil<float>));

	bind("double absfloor(double)", asFUNCTION(absfloor<double>));
	bind("float absfloor(float)", asFUNCTION(absfloor<float>));

	bind("double angleDiff(double a, double b)", asFUNCTION(angleDiff));
	bind("void quarticRoots(double a, double b, double c, double d, double e, array<double>& roots)", asFUNCTION(QuarticRoots))
		doc("Calculates all real roots of a quartic polynomial.", "Coefficient A", "Coefficient B", "Coefficient C", "Coefficient D", "Coefficient E", "Array to return roots in.");

	bind("double newtonArrivalTime(double accel, const vec3d& offset, const vec3d& relativeVelocity)", asFUNCTION(newtonArrivalTime));

	//String manipulation
	bind("void u8append(string&, int)", asFUNCTION(u8append));
	bind("int u8pos(const string &in, int, int)", asFUNCTION(u8pos));
	bind("int u8get(const string &in, int)", asFUNCTION(u8get));
	bind("void u8next(const string &in, int&, int&)", asFUNCTION(u8next));
	bind("void u8prev(const string &in, int&, int&)", asFUNCTION(u8prev));
	bind("int u8(int)", asFUNCTION(u8prev));

	bind("void appendRoman(int num, const string& str)", asFUNCTIONPR(romanNumerals, (unsigned, std::string&), void));
	bind("void toLowercase(string&)", asFUNCTION(toLowercase));
	bind("void toUppercase(string&)", asFUNCTION(toUppercase));
	bind("uint8 uppercase(uint8)", asFUNCTION(uppercase));
	bind("uint8 lowercase(uint8)", asFUNCTION(lowercase));
	bind("string unescape(const string&in)", asFUNCTION(unescape));
	bind("string escape(const string&in)", asFUNCTION(escape));

	bind("string localize(const string& in, bool requireHash = false, bool doUnescape = true)", asFUNCTION(localize));
	bind("Color toColor(const string& in)", asFUNCTION(toColor));

	bind("string toString(double num, uint precision = 5)", asFUNCTION(toString<double>));
	bind("string toString(float num, uint precision = 5)", asFUNCTION(toString<float>));
	bind("string toString(int num, uint precision = 5)", asFUNCTION(toString<int>));
	bind("string toString(uint num, uint precision = 5)", asFUNCTION(toString<unsigned>));
	bind("string toString(Color color)", asFUNCTION(toString<Color>));

	bind("string standardize(double value, bool showIntegral = false, bool roundUp = false)", asFUNCTION(standardize));
	bind("bool funcSplit(const string& input, string&out funcName, array<string>& arguments, bool strip = true)", asFUNCTION(scriptFuncSplit));

	bind("float toFloat(const string &in str)", asFUNCTION(wrap_toNumber<float>));
	bind("double toDouble(const string &in str)", asFUNCTION(wrap_toNumber<double>));
	bind("int toInt(const string &in str)", asFUNCTION(wrap_toNumber<int>));
	bind("uint toUInt(const string &in str)", asFUNCTION(wrap_toNumber<unsigned>));

	bind("bool toBool(const string &in str)", asFUNCTION(wrap_toBool));

	bind("vec3d toVec3d(const string &in str)", asFUNCTION(toVec3d))
		doc("Parses a vec3d printed by vec3d::toString()", "", "");

	//Add stuff to string
	ClassBind str("string");
	str.addExternMethod("bool toBool() const", asFUNCTION(wrap_toBool));
	str.addExternMethod("int toInt() const", asFUNCTION(wrap_toNumber<int>));
	str.addExternMethod("uint toUint() const", asFUNCTION(wrap_toNumber<unsigned>));
	str.addExternMethod("float toFloat() const", asFUNCTION(wrap_toNumber<float>));
	str.addExternMethod("double toDouble() const", asFUNCTION(wrap_toNumber<double>));
	str.addExternMethod("vec3d toVec3d() const", asFUNCTION(toVec3d));

	str.addExternMethod("string trimmed() const", asFUNCTIONPR(trim, (const std::string&), std::string));
	str.addExternMethod("string& paragraphize(const string& parSep, const string& lineSep, bool startsParagraph = false)", asFUNCTION(paragraphize));
	str.addExternMethod("string& replace(const string& replace, const string& with)", asFUNCTION(replace));
	str.addExternMethod("string replaced(const string& replace, const string& with) const", asFUNCTION(replaced));
	str.addExternMethod("bool isWhitespace() const", asFUNCTION(strIsWhitespace));
	str.addExternMethod("bool contains(const string &in) const", asFUNCTION(strContains));
	str.addExternMethod("bool contains_nocase(const string &in) const", asFUNCTION(strContainsNC));
	str.addExternMethod("int findFirst_nocase(const string &in, uint start = 0) const", asFUNCTION(strfind_nocase));
	str.addExternMethod("bool startswith(const string &in) const", asFUNCTION(startsWith));
	str.addExternMethod("bool endswith(const string &in) const", asFUNCTION(endsWith));
	str.addExternMethod("bool startswith_nocase(const string &in) const", asFUNCTION(startsWithNC));
	str.addExternMethod("bool endswith_nocase(const string &in) const", asFUNCTION(endsWithNC));
	str.addExternMethod("bool equals(const string &in, int start) const", asFUNCTION(strEq_s));
	str.addExternMethod("bool equals(const string &in, int start, int length) const", asFUNCTION(strEq_sl));
	str.addExternMethod("bool equals_nocase(const string &in, int start = 0) const", asFUNCTION(strEqNC_s));
	str.addExternMethod("bool equals_nocase(const string &in, int start, int length) const", asFUNCTION(strEqNC_sl));

	if(!server) {
		bind("void setClipboard(const string &in)", asFUNCTION(copyToClipboard));
		bind("string getClipboard()", asFUNCTION(readFromClipboard));
	}

	//Adding console commands
	InterfaceBind ccomm("ConsoleCommand");
	classdoc(ccomm, "Interface to implement for script console commands.");

	asIScriptFunction* pConsoleCommand;
	ccomm.addMethod("void execute(const string& args)", &pConsoleCommand)
		doc("Called whenever this command was invoked, with all extra text passed to the command.", "Additional text passed after the command.");

	getEngine()->SetUserData(pConsoleCommand, EDID_consoleCommand);

	bind("void addConsoleCommand(const string& name, ConsoleCommand@ comm)", asFUNCTION(addConsComm))
		doc("Registers a script console command.", "Command name to use the command.", "Instance of a command to call.");
	bind("void toggleConsole()", asFUNCTION(toggleConsole));

	//Constants
	bindGlobal("const double e", (void*)&e);
	bindGlobal("const double pi", (void*)&pi);
	bindGlobal("const double twopi", (void*)&twopi);

	//Special print functions are used by the console
	//to print the resulting values of a command line
	bind("void print(bool)", asFUNCTIONPR(_print, (bool), void));
	bind("void print(int)", asFUNCTIONPR(_print, (int), void));
	bind("void print(uint)", asFUNCTIONPR(_print, (unsigned), void));
	bind("void print(float)", asFUNCTIONPR(_print, (float), void));
	bind("void print(double)", asFUNCTIONPR(_print, (double), void));
	bind("void print(const ?&)", asFUNCTIONPR(_print, (void*, int), void));
	bind("void print()", asFUNCTIONPR(_print, (), void));
	bind("void printTrace(bool verbose = false)", asFUNCTION(logExc));
	bind("uint64 addressof(const ?&)", asFUNCTION(dbgAddress));
	bind("string addrstr(const ?&)", asFUNCTION(strPointer));
	bind("string dbgstr(const ?&)", asFUNCTION(dbgStr));
	bind("void dbg(const ?&, const string& prefix = \"\")", asFUNCTION(dbgOut));
	bind("void dbg(const string& prefix = \"\")", asFUNCTION(dbgAll));
	bind("int refcnt(const ?&)", asFUNCTION(getRefCnt));

	//Locale access
	bind("string format(const string &in fmt, const string &in)", asFUNCTION(format_1))
		doc("Replaces $n in fmt with the related argument.", "Format to use.", "$1", "Formatted string.");
	bind("string format(const string &in fmt, const string &in, const string &in)", asFUNCTION(format_2))
		doc("Replaces $n in fmt with the related argument.", "Format to use.", "$1", "$2", "Formatted string.");
	bind("string format(const string &in fmt, const string &in, const string &in, const string &in)", asFUNCTION(format_3))
		doc("Replaces $n in fmt with the related argument.", "Format to use.", "$1", "$2", "$3", "Formatted string.");
	bind("string format(const string &in fmt, const string &in, const string &in, const string &in, const string &in)", asFUNCTION(format_4))
		doc("Replaces $n in fmt with the related argument.", "Format to use.", "$1", "$2", "$3", "$4", "Formatted string.");
	bind("string format(const string &in fmt, const string &in, const string &in, const string &in, const string &in, const string &in)", asFUNCTION(format_5))
		doc("Replaces $n in fmt with the related argument.", "Format to use.", "$1", "$2", "$3", "$4", "$5", "Formatted string.");
	bind("string format(const string &in fmt, const array<string>& args)", asFUNCTION(format_n))
		doc("Replaces $n in fmt with the related argument.", "Format to use.", "Arguments.", "Formatted string.");

	//Cloud stuff
	{
		Namespace ns("cloud");
		bind("bool get_isActive()", asFUNCTION(isCloudActive));
		bind("bool get_inLobby()", asFUNCTION(inCloudLobby));
		bind("string getNickname()", asFUNCTION(getCloudNickname));
		bind("void inviteFriend()", asFUNCTION(inviteCloudFriend));
		bind("void enterQueue(const string& type, uint players, const string& version)", asFUNCTION(enterCloudQueue));
		bind("bool get_isQueueReady()", asFUNCTION(cloudQueueReady));
		bind("bool get_queueRequest()", asFUNCTION(cloudQueueRequest));
		bind("bool get_inQueue()", asFUNCTION(cloudInQ));
		bind("void leaveQueue()", asFUNCTION(cloudQLeave));
		bind("void acceptQueue()", asFUNCTION(cloudQAccept));
		bind("void rejectQueue()", asFUNCTION(cloudQReject));
		bind("int queueTimer()", asFUNCTION(cloudQTime));
		bind("uint get_queuePlayers()", asFUNCTION(cloudQPlayers));
		bind("bool getQueuePlayerWait(uint &out ready, uint &out cap)", asFUNCTION(cloudQWaiting));

		bind("void prepItem(const string& folder)", asFUNCTION(cloudCreateItem))
			doc("Prepares an item for updating or creation. Wait a few frames for cloud::itemReady to be true.");
		bind("void closeItem()", asFUNCTION(cloudCloseItem));
		bind("bool get_itemReady()", asFUNCTION(cloudItemReady));
		bind("uint64 get_itemID()", asFUNCTION(cloudItemID));
		bind("void set_itemTitle(const string&)", asFUNCTION(cloudItemTitle));
		bind("void set_itemDescription(const string&)", asFUNCTION(cloudItemDesc));
		bind("void setItemContent(const string& folder)", asFUNCTION(cloudItemFolder));
		bind("void setItemImage(const string& filename)", asFUNCTION(cloudItemImage));
		bind("void setItemTags(array<string>& tags)", asFUNCTION(cloudItemTags));
		bind("void setItemPublic()", asFUNCTION(cloudItemVisible));
		bind("void commitItem(const string& changelog)", asFUNCTION(cloudItemCommit));
		bind("double get_uploadProgress()", asFUNCTION(cloudItemProgress));
		bind("bool get_isUploading()", asFUNCTION(cloudItemUploading));
		bind("void openLegalPrompt()", asFUNCTION(cloudLegal));
	}

	//Key actions
	EnumBind ka("KeyAction");
	ka["KA_Pressed"] = os::KA_Pressed;
	ka["KA_Released"] = os::KA_Released;
	ka["KA_Repeated"] = os::KA_Repeated;

	//Key constants
	EnumBind kc("KeyCode");
	for(unsigned int i = 0; i < 26; ++i) {
		std::string keyName = "KEY_";
		keyName.push_back(char('A' + i));

		std::string logicalName = "KEY_LOGICAL_";
		logicalName.push_back(char('A' + i));

		kc[keyName] = os::KEY_A + i;
		kc[logicalName] = devices.driver->getKeyForChar('A'+i);
	}

	kc["KEY_ESC"] = os::KEY_ESC;
	kc["KEY_F1"] = os::KEY_F1;
	kc["KEY_F2"] = os::KEY_F2;
	kc["KEY_F3"] = os::KEY_F3;
	kc["KEY_F4"] = os::KEY_F4;
	kc["KEY_F5"] = os::KEY_F5;
	kc["KEY_F6"] = os::KEY_F6;
	kc["KEY_F7"] = os::KEY_F7;
	kc["KEY_F8"] = os::KEY_F8;
	kc["KEY_F9"] = os::KEY_F9;
	kc["KEY_F10"] = os::KEY_F10;
	kc["KEY_F11"] = os::KEY_F11;
	kc["KEY_F12"] = os::KEY_F12;
	kc["KEY_F13"] = os::KEY_F13;
	kc["KEY_F14"] = os::KEY_F14;
	kc["KEY_F15"] = os::KEY_F15;
	kc["KEY_F16"] = os::KEY_F16;
	kc["KEY_F17"] = os::KEY_F17;
	kc["KEY_F18"] = os::KEY_F18;
	kc["KEY_F19"] = os::KEY_F19;
	kc["KEY_F20"] = os::KEY_F20;
	kc["KEY_F21"] = os::KEY_F21;
	kc["KEY_F22"] = os::KEY_F22;
	kc["KEY_F23"] = os::KEY_F23;
	kc["KEY_F24"] = os::KEY_F24;
	kc["KEY_F25"] = os::KEY_F25;
	kc["KEY_UP"] = os::KEY_UP;
	kc["KEY_DOWN"] = os::KEY_DOWN;
	kc["KEY_LEFT"] = os::KEY_LEFT;
	kc["KEY_RIGHT"] = os::KEY_RIGHT;
	kc["KEY_LSHIFT"] = os::KEY_LSHIFT;
	kc["KEY_RSHIFT"] = os::KEY_RSHIFT;
	kc["KEY_LCTRL"] = os::KEY_LCTRL;
	kc["KEY_RCTRL"] = os::KEY_RCTRL;
	kc["KEY_LALT"] = os::KEY_LALT;
	kc["KEY_RALT"] = os::KEY_RALT;
	kc["KEY_TAB"] = os::KEY_TAB;
	kc["KEY_ENTER"] = os::KEY_ENTER;
	kc["KEY_BACKSPACE"] = os::KEY_BACKSPACE;
	kc["KEY_INSERT"] = os::KEY_INSERT;
	kc["KEY_DEL"] = os::KEY_DEL;
	kc["KEY_PAGEUP"] = os::KEY_PAGEUP;
	kc["KEY_PAGEDOWN"] = os::KEY_PAGEDOWN;
	kc["KEY_HOME"] = os::KEY_HOME;
	kc["KEY_END"] = os::KEY_END;
	kc["KEY_KP_0"] = os::KEY_KP_0;
	kc["KEY_KP_1"] = os::KEY_KP_1;
	kc["KEY_KP_2"] = os::KEY_KP_2;
	kc["KEY_KP_3"] = os::KEY_KP_3;
	kc["KEY_KP_4"] = os::KEY_KP_4;
	kc["KEY_KP_5"] = os::KEY_KP_5;
	kc["KEY_KP_6"] = os::KEY_KP_6;
	kc["KEY_KP_7"] = os::KEY_KP_7;
	kc["KEY_KP_8"] = os::KEY_KP_8;
	kc["KEY_KP_9"] = os::KEY_KP_9;
	kc["KEY_KP_DIVIDE"] = os::KEY_KP_DIVIDE;
	kc["KEY_KP_MULTIPLY"] = os::KEY_KP_MULTIPLY;
	kc["KEY_KP_SUBTRACT"] = os::KEY_KP_SUBTRACT;
	kc["KEY_KP_ADD"] = os::KEY_KP_ADD;
	kc["KEY_KP_DECIMAL"] = os::KEY_KP_DECIMAL;
	kc["KEY_KP_EQUAL"] = os::KEY_KP_EQUAL;
	kc["KEY_KP_ENTER"] = os::KEY_KP_ENTER;
	kc["KEY_NUM_LOCK"] = os::KEY_NUM_LOCK;
	kc["KEY_CAPS_LOCK"] = os::KEY_CAPS_LOCK;
	kc["KEY_SCROLL_LOCK"] = os::KEY_SCROLL_LOCK;
	kc["KEY_PAUSE"] = os::KEY_PAUSE;
	kc["KEY_LSUPER"] = os::KEY_LSUPER;
	kc["KEY_RSUPER"] = os::KEY_RSUPER;
	kc["KEY_MENU"] = os::KEY_MENU;
}

};

int FindCubicRoots(const double coeff[4], double x[3]) {
	/* Adjust coefficients */
	double a1 = coeff[2] / coeff[3];
	double a2 = coeff[1] / coeff[3];
	double a3 = coeff[0] / coeff[3];

	double Q = (a1 * a1 - 3 * a2) / 9;
	double R = (2 * a1 * a1 * a1 - 9 * a1 * a2 + 27 * a3) / 54;
	double Qcubed = Q * Q * Q;
	double d = Qcubed - R * R;

	/* Three real roots */
	if (d>=0)
	{
		double theta = acos(R / sqrt(Qcubed));
		double sqrtQ = sqrt(Q);

		x[0] = -2 * sqrtQ * cos( theta / 3) - a1 / 3;
		x[1] = -2 * sqrtQ * cos((theta + 2 * pi) / 3) - a1 / 3;
		x[2] = -2 * sqrtQ * cos((theta + 4 * pi) / 3) - a1 / 3;

		return (3);
	}
	/* One real root */
	else
	{
		double e = pow(sqrt(-d) + fabs(R), 1. / 3.);

		if (R > 0) e = -e;

		x[0] = (e + Q / e) - a1 / 3.;

		return (1);
	}
}

int FindQuarticRoots(const double coeff[5], double x[4]) {
	/* Adjust coefficients */

	double a1 = coeff[3] / coeff[4];
	double a2 = coeff[2] / coeff[4];
	double a3 = coeff[1] / coeff[4];
	double a4 = coeff[0] / coeff[4];

	/* Reduce to solving cubic equation */

	double q = a2 - a1*a1*3/8;
	double r = a3 - a1*a2/2 + a1*a1*a1/8;
	double s = a4 - a1*a3/4 + a1*a1*a2/16 - 3*a1*a1*a1*a1/256;

	double coeff_cubic[4];
	double roots_cubic[3];
	double positive_root;

	coeff_cubic[3] = 1;
	coeff_cubic[2] = q/2;
	coeff_cubic[1] = (q*q-4*s)/16;
	coeff_cubic[0] = -r*r/64;

	int nRoots = FindCubicRoots(coeff_cubic,roots_cubic);

	for (int i=0; i<nRoots; i++)
		if (roots_cubic[i]>0) {
			positive_root = roots_cubic[i];
			break; //ADDED
		}

	/* Reduce to solving two quadratic equations */

	double k = sqrt(positive_root);
	double l = 2*k*k + q/2 - r/(4*k);
	double m = 2*k*k + q/2 + r/(4*k);

	nRoots = 0;

	if (k*k-l>0)
	{
		x[nRoots+0] = -k - sqrt(k*k-l) - a1/4;
		x[nRoots+1] = -k + sqrt(k*k-l) - a1/4;

		nRoots += 2;
	}

	if (k*k-m>0)
	{
		x[nRoots+0] = +k - sqrt(k*k-m) - a1/4;
		x[nRoots+1] = +k + sqrt(k*k-m) - a1/4;

		nRoots += 2;
	}

	return nRoots;
}
