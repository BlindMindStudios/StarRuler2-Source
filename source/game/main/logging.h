#pragma once
#include "threads.h"
#include <string>

enum LogLevel {
	LL_Error,
	LL_Warning,
	LL_Info,
};

void setLogLevel(LogLevel level);
LogLevel getLogLevel();
void createLog();
void flushLog();
void storeLog(const std::string& filename);

void info(const std::string& msg);
void warn(const std::string& msg);
void error(const std::string& msg);

void info(const char* format, ...);
void warn(const char* format, ...);
void error(const char* format, ...);

void print(const std::string& msg);
void print(const char* format, ...);

void print(LogLevel lvl, const std::string& msg);
void print(LogLevel lvl, const char* format, ...);

void printv(const char* format, va_list ap);

void appendToErrorLog(const std::string& errMsg, bool timestamp = true);
void appendToErrorLog(const char* errMsg, bool timestamp = true, bool separateLogs = true);

void logDate();

enum NativeSection {
	NS_Unknown,
	NS_Network,
	NS_Processing,
	NS_Loading,
	NS_ScriptTick,
	NS_Render,
	NS_Startup,
	NS_MessageThread,
	NS_Animation,

	NS_COUNT
};

//Sets the current section, returning the previous section
NativeSection enterSection(NativeSection section);
const char* getSectionName();
