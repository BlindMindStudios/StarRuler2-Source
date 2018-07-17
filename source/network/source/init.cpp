#include <network/init.h>
#include "threads.h"

#ifdef _MSC_VER
#include <WinSock2.h>
#include <ws2def.h>
#include <ws2ipdef.h>
#include <WS2tcpip.h>
#endif

namespace net {

netErrorCallback errorCallback = nullptr;

void setErrorCallback(netErrorCallback cb) {
	errorCallback = cb;
}

void netError(const char* err, int code) {
	if(errorCallback)
		errorCallback(err, code);
}

#ifdef _MSC_VER
threads::Mutex ws_mutex;
unsigned ws_usage = 0;

bool prepare() {
	threads::Lock lock(ws_mutex);
	if(ws_usage == 0) {
		WSAData winSockInfo;
		int result = WSAStartup(MAKEWORD(2,2), &winSockInfo);
		if(result != 0) {
			netError("Failed to initialize network", WSAGetLastError());
			return false;
		}
	}
	ws_usage += 1;
	return true;
}

void clear() {
	threads::Lock lock(ws_mutex);
	if(--ws_usage == 0)
		WSACleanup();
}
#else
bool prepare() {
	return true;
}

void clear() {
}
#endif

};
