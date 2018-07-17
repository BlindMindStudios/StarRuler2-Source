#pragma once

namespace net {

typedef void (*netErrorCallback)(const char* message, int code);

void setErrorCallback(netErrorCallback cb);
void netError(const char* err, int code);

bool prepare();
void clear();
	
};
