#pragma once
#include "angelscript.h"
#include "threads.h"
#include <string>
#include <vector>
#include <stack>
#include <map>

//Logs every line that triggers a line callback
//#define LOG_EXECUTION

//Samples all execution randomly, recording results
//	The define also specifies how often to check for an executed line (higher is less often)
//#define PROFILE_EXECUTION 25

#if defined(LOG_EXECUTION) || defined(PROFILE_EXECUTION)
#define DO_LINE_CALLBACK
#endif

namespace scripts {

void initContextCache();
void resetContextCache(bool resetMenu = false);
void freeContextCache();

asIScriptContext* makeContext(asIScriptEngine* engine);
asIScriptContext* fetchContext(asIScriptEngine* engine);

std::string getStackVariables(asIScriptContext* context, unsigned frame = 0);
std::string getStackTrace(asIScriptContext* context, bool verbose = false);
std::string getScriptVariable(void *value, asUINT typeId, bool expandMembers, asIScriptEngine *engine);
void logException();

};
