#include "main/logging.h"
#include "main/console.h"
#include "str_util.h"
#include "files.h"
#include <stdio.h>
#include <stdarg.h>
#include <iostream>
#include <fstream>
#include <time.h>
	
LogLevel level = LL_Warning;
std::ofstream logFile;
std::fstream errorLog;

void createLog() {
	logFile.open(path_join(getProfileRoot(), "log.txt"), std::ofstream::trunc | std::ofstream::out);
	errorLog.open(path_join(getProfileRoot(), "errors.log.txt"), std::fstream::out | std::fstream::app);
}

void flushLog() {
	logFile.flush();
	errorLog.flush();
}

void logDate() {
	time_t stamp = time(NULL);
	struct tm* timeinfo;
	timeinfo = localtime(&stamp);
	char buffer[125];
	strftime(buffer, 124, "%d %b %Y %H:%M:%S\n", timeinfo);
	logFile << buffer;
}

void appendToErrorLog(const char* errMsg, bool timestamp, bool separateLogs) {
	if(timestamp) {
		time_t stamp = time(NULL);
		struct tm* timeinfo;
		timeinfo = localtime(&stamp);
		char buffer[125];
		strftime(buffer, 124, "%d %b %Y %H:%M:%S\n", timeinfo);
		errorLog << buffer;
	}

	errorLog << errMsg;
	if(separateLogs)
		errorLog << "\n\n";
	else
		errorLog << "\n";
	errorLog.flush();
}

void appendToErrorLog(const std::string& errMsg, bool timestamp) {
	appendToErrorLog(errMsg.c_str(), timestamp);
}

void storeLog(const std::string& filename) {
	//NOTE: This only happens during a crash situation, so we disregard the various possible side effects if something goes wrong
	logFile.flush();
	logFile.close();
	std::string logPath = path_join(getProfileRoot(), "log.txt");
	rename(logPath.c_str(), filename.c_str());
}


void setLogLevel(LogLevel level) {
	::level = level;
}

LogLevel getLogLevel() {
	return level;
}

void print(const std::string& msg) {
	printf("%s\n", msg.c_str());
	logFile << msg << std::endl;
	console.printLn(msg);
}

void print(const char* format, ...) {
	va_list ap;
	va_start(ap, format);
	printv(format, ap);
	va_end(ap);
}

void printv(const char* format, va_list ap) {
	char line[2048];
	vsnprintf(line, 2048, format, ap);
	printf("%s\n", line);
	logFile << line << std::endl;
	console.printLn(line);
}

void info(const std::string& msg) {
	if(level >= LL_Info)
		print(msg);
}

void info(const char* format, ...) {
	va_list ap;
	va_start(ap, format);
	if(level >= LL_Info)
		printv(format, ap);
	va_end(ap);
}

void warn(const std::string& msg) {
	if(level >= LL_Warning)
		print(msg);
}

void warn(const char* format, ...) {
	if(level >= LL_Warning) {
		va_list ap;
		va_start(ap, format);
			printv(format, ap);
		va_end(ap);
	}
}

void error(const std::string& msg) {
	if(level >= LL_Error)
		print(msg);
}

void error(const char* format, ...) {
	if(level >= LL_Error) {
		va_list ap;
		va_start(ap, format);
			printv(format, ap);
		va_end(ap);
	}
}

void print(LogLevel lvl, const std::string& msg) {
	if(level >= lvl)
		print(msg);
}

void print(LogLevel lvl, const char* format, ...) {
	if(level >= lvl) {
		va_list ap;
		va_start(ap, format);
			printv(format, ap);
		va_end(ap);
	}
}

const char* sectionNames[NS_COUNT] = {
	"Unknown",
	"Network",
	"Processing",
	"Loading",
	"Script Tick",
	"Render",
	"Startup",
	"Message Thread",
	"Animation"
};

Threaded(NativeSection) threadSection = NS_Unknown;

NativeSection enterSection(NativeSection section) {
	auto& sect = threadSection;
	NativeSection n = sect;
	sect = section;
	return n;
}

const char* getSectionName() {
	if(threadSection < NS_COUNT)
		return sectionNames[threadSection];
	else
		return sectionNames[NS_Unknown];
}
