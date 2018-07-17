#include "context_cache.h"
#include "main/logging.h"
#include "compat/misc.h"
#include "str_util.h"
#include "files.h"
#include "util/format.h"
#include <unordered_map>
#include <unordered_set>
#include <set>
#include <stack>
#include "main/references.h"

#ifndef MAX_CACHED_CALLS
	#define MAX_CACHED_CALLS 512
#endif

#ifndef MAX_AS_CALLSTACK_PRINT_DEPTH
	#define MAX_AS_CALLSTACK_PRINT_DEPTH 64
#endif

#ifdef PROFILE_EXECUTION

#include "../main/references.h"

struct ScriptStep {
	asIScriptFunction* func;
	int line;
	mutable unsigned long long count;

	bool operator<(const ScriptStep& other) const {
		if(count > other.count)
			return true;
		else if(count == other.count) {
			if(func > other.func)
				return true;
			else if(func == other.func && line > other.line)
				return true;
		}
		return false;
	}

	bool operator==(const ScriptStep& other) const {
		return func == other.func && line == other.line;
	}
	
	ScriptStep() : func(0), line(0), count(0) {}
	ScriptStep(asIScriptFunction* f, int l) : func(f), line(l), count(0) {}
};

namespace std {
template<>
struct hash<ScriptStep> {
	size_t operator()(const ScriptStep& step) const {
		return (size_t)step.func ^ (size_t)step.line;
	};
};
};
#endif

bool LOG_CHATTY = false;
bool LOG_ERRORLOG = true;

namespace scripts {

struct ContextCache {
	asIScriptContext* menuCtx;
	asIScriptContext* clientCtx;
	asIScriptContext* serverCtx;

	ContextCache() : menuCtx(0), clientCtx(0), serverCtx(0) {
	}

	void reset(bool resetMenu = false) {
		if(resetMenu && menuCtx) {
			menuCtx->Release();
			menuCtx = 0;
		}

		if(clientCtx) {
			clientCtx->Release();
			clientCtx = 0;
		}

		if(serverCtx) {
			serverCtx->Release();
			serverCtx = 0;
		}
	}
};

Threaded(ContextCache*) ctxCache = 0;

//Special logging/profiling systems via line callback
#ifdef DO_LINE_CALLBACK

#ifdef PROFILE_EXECUTION
threads::atomic_int profile_step;
threads::Mutex profile_lock;

typedef std::unordered_set<ScriptStep> scriptSteps;
std::unordered_map<asIScriptEngine*,scriptSteps*> scriptSets;

void logScriptProfile(asIScriptEngine* engine) {
	profile_lock.lock();
	auto iSet = scriptSets.find(engine);
	if(iSet != scriptSets.end()) {
		//Order steps by number of hits
		std::set<ScriptStep> orderedSteps;
		for(auto i = iSet->second->begin(), end = iSet->second->end(); i != end; ++i)
			orderedSteps.insert(*i);
		//We don't need the shared data now
		profile_lock.release();

		//Print line counts that registered more than 10 counts
		for(auto i = orderedSteps.begin(), end = orderedSteps.end(); i != end && i->count > 10; ++i)
			print("\t%8lld: %s line %d in %s", i->count, i->func->GetScriptSectionName(), i->line, i->func->GetName());
	}
	else {
		profile_lock.release();
	}
}

Threaded(double*) lastStep = 0;

#endif

void TraceExec(asIScriptContext *ctx, void *arg)
{
#ifdef LOG_EXECUTION
	std::string msg;
	for( asUINT n = 0; n < ctx->GetCallstackSize(); n++ )
		msg += " ";
	msg += ctx->GetFunction()->GetDeclaration();
	if(void* ptr = ctx->GetThisPointer()) {
		msg += "@";
		msg += toString((unsigned int)ptr);
	}
	msg += "    Line: ";
	msg += toString(ctx->GetLineNumber());
	print(msg);
#endif
#ifdef PROFILE_EXECUTION
	if(++profile_step % PROFILE_EXECUTION == 0) {
		double*& pLastTime = lastStep;
		if(pLastTime == 0)
			pLastTime = new double(0);

		double time = devices.driver->getAccurateTime();
		if(time - *pLastTime > 0.000001) {
			*pLastTime = time;
			ScriptStep step(ctx->GetFunction(),ctx->GetLineNumber());
			profile_lock.lock();

			auto iSet = scriptSets.find(ctx->GetEngine());
			scriptSteps* set;

			if(iSet != scriptSets.end()) {
				set = iSet->second;
			}
			else {
				set = new scriptSteps;
				scriptSets[ctx->GetEngine()] = set;
			}

			auto iStep = set->find(step);
			if(iStep != set->end()) {
				++iStep->count;
			}
			else {
				step.count = 1;
				set->insert(step);
			}

			profile_lock.release();
		}
	}
#endif
}
#endif

void logException(asIScriptContext* context) {
	error("Script Exception: %s", context->GetExceptionString());
	error(getStackTrace(context, true));
}

threads::Mutex errMtx;
std::unordered_set<std::string> printedErrors;

void excCallback(asIScriptContext* context) {
	std::string errMsg;
	errMsg += "Script Exception: ";
	errMsg += context->GetExceptionString();
	errMsg += "\n";
	errMsg += getStackTrace(context);

	if(!LOG_CHATTY) {
		threads::Lock lck(errMtx);
		if(printedErrors.find(errMsg) != printedErrors.end())
			return;
		printedErrors.insert(errMsg);
	}

	//Add to normal log
	error(errMsg);
	flushLog();

	//Add to error log
	if(LOG_ERRORLOG)
		appendToErrorLog(errMsg);
}

void logException() {
	auto* ctx = asGetActiveContext();
	if(ctx)
		logException(ctx);
	else
		error("No active script context to log.");
	flushLog();
}

std::string getStackVariables(asIScriptContext* context, unsigned frame) {
	std::string trace, line;
	for(unsigned n = 0, ncnt = context->GetVarCount(frame); n < ncnt; ++n) {
		if(!context->IsVarInScope(n, frame))
			continue;
		line += context->GetVarDeclaration(n, frame, false);
		line += " = ";
		line += getScriptVariable(
			context->GetAddressOfVar(n, frame),
			context->GetVarTypeId(n, frame),
			true,
			context->GetEngine());
		line += "; ";
		if(line.size() > 100) {
			trace += line+"\n";
			line.clear();
		}
	}
	if(!line.empty())
		trace += line+"\n";

	void* ptr = context->GetThisPointer(frame);
	if(ptr != nullptr) {
		int thisType = context->GetThisTypeId(frame);
		if(thisType >= 0) {
			trace += context->GetEngine()->GetTypeDeclaration(thisType);
			trace += " this = ";
			trace += getScriptVariable(ptr, thisType, true, context->GetEngine());
			trace += ";\n";
		}
	}
	return trace;
}

std::string getStackTrace(asIScriptContext* context, bool verbose) {
	std::string trace;

	int cnt = std::min((int)context->GetCallstackSize(), MAX_AS_CALLSTACK_PRINT_DEPTH);
	for(int i = 0; i < cnt; ++i) {
		asIScriptFunction* func = context->GetFunction(i);
		
		if(func) {
			if(i == 0) {
				const char* section = func->GetScriptSectionName();
				if(section)
					trace += std::string(" ") + section + "\n";
				else
					trace += " <Unknown>\n";
			}

			int line, column;
			line = context->GetLineNumber(i, &column);

			trace += format("  $1::$2 | Line $3 | Col $4\n", func->GetModuleName(), func->GetDeclaration(), line, column);
		}
		else {
			trace += "  <Unknown function>\n";
		}
	}

	/*if(cnt != 0 && (verbose || getLogLevel() >= LL_Info)) {
		trace += "########################################\n";
		trace += getStackVariables(context);
		trace += "########################################\n";
	}*/

	return trace;
}

asIScriptContext* makeContext(asIScriptEngine* engine) {
	asIScriptContext* ctx = engine->CreateContext();
	ctx->SetExceptionCallback(asFUNCTIONPR(excCallback, (asIScriptContext*), void), 0, asCALL_CDECL);
#ifdef DO_LINE_CALLBACK
	ctx->SetLineCallback(asFUNCTION(TraceExec), 0, asCALL_CDECL);
#endif
	return ctx;
}

std::vector<ContextCache*> caches;
threads::Mutex cacheMtx;

void initContextCache() {
	ctxCache = new ContextCache();

	{
		threads::Lock lock(cacheMtx);
		caches.push_back(ctxCache);
	}
}

void freeContextCache() {
	{
		threads::Lock lock(cacheMtx);
		auto it = std::find(caches.begin(), caches.end(), ctxCache);
		if(it != caches.end())
			caches.erase(it);
	}

	delete ctxCache;
}

void resetContextCache(bool resetMenu) {
	//Only call this if no scripts will run for sure
	threads::Lock lock(cacheMtx);
	foreach(it, caches)
		(*it)->reset(resetMenu);
}

asIScriptContext* fetchContext(asIScriptEngine* engine) {
	ContextCache* cache = ctxCache;

	if(engine == devices.engines.server) {
		auto* ctx = cache->serverCtx;
		if(!ctx) {
			ctx = makeContext(engine);
			cache->serverCtx = ctx;
		}
		return ctx;
	}
	else if(engine == devices.engines.client) {
		auto* ctx = cache->clientCtx;
		if(!ctx) {
			ctx = makeContext(engine);
			cache->clientCtx = ctx;
		}
		return ctx;
	}
	else { //menu
		auto* ctx = cache->menuCtx;
		if(!ctx) {
			ctx = makeContext(engine);
			cache->menuCtx = ctx;
		}
		return ctx;
	}
}

std::string getScriptVariable(void *value, asUINT typeId, bool expandMembers, asIScriptEngine *engine) {
	//From the AS debugger addon
	std::stringstream s;
	if( typeId == asTYPEID_VOID )
		return "<void>";
	else if( typeId == asTYPEID_BOOL )
		return *(bool*)value ? "true" : "false";
	else if( typeId == asTYPEID_INT8 )
		s << (int)*(signed char*)value;
	else if( typeId == asTYPEID_INT16 )
		s << (int)*(signed short*)value;
	else if( typeId == asTYPEID_INT32 )
		s << *(signed int*)value;
	else if( typeId == asTYPEID_INT64 )
#if defined(_MSC_VER) && _MSC_VER <= 1200
		s << "{...}"; // MSVC6 doesn't like the << operator for 64bit integer
#else
		s << *(asINT64*)value;
#endif
	else if( typeId == asTYPEID_UINT8 )
		s << (unsigned int)*(unsigned char*)value;
	else if( typeId == asTYPEID_UINT16 )
		s << (unsigned int)*(unsigned short*)value;
	else if( typeId == asTYPEID_UINT32 )
		s << *(unsigned int*)value;
	else if( typeId == asTYPEID_UINT64 )
#if defined(_MSC_VER) && _MSC_VER <= 1200
		s << "{...}"; // MSVC6 doesn't like the << operator for 64bit integer
#else
		s << *(asQWORD*)value;
#endif
	else if( typeId == asTYPEID_FLOAT )
		s << *(float*)value;
	else if( typeId == asTYPEID_DOUBLE )
		s << *(double*)value;
	else if( (typeId & asTYPEID_MASK_OBJECT) == 0 )
	{
		// The type is an enum
		s << *(asUINT*)value;

		// Check if the value matches one of the defined enums
		/*for( int n = engine->GetEnumValueCount(typeId); n-- > 0; )
		{
			int enumVal;
			const char *enumName = engine->GetEnumValueByIndex(typeId, n, &enumVal);
			if( enumVal == *(int*)value )
			{
				s << ", " << enumName;
				break;
			}
		}*/
	}
	else if( typeId & asTYPEID_SCRIPTOBJECT )
	{
		// Dereference handles, so we can see what it points to
		if( typeId & asTYPEID_OBJHANDLE )
			value = *(void**)value;

		asIScriptObject *obj = (asIScriptObject *)value;

		s << "{ " << obj << "";

		if( obj && expandMembers )
		{
			asITypeInfo *type = obj->GetObjectType();
			for( unsigned n = 0; n < obj->GetPropertyCount(); n++ )
			{
				s << std::endl << "  " << type->GetPropertyDeclaration(n) << " = " << getScriptVariable(obj->GetAddressOfProperty(n), obj->GetPropertyTypeId(n), false, engine);
			}
			s << "\n}";
		}
		else {
			s << " }";
		}
	}
	else
	{
		// Dereference handles, so we can see what it points to
		if( typeId & asTYPEID_OBJHANDLE )
			value = *(void**)value;

		auto* type = engine->GetTypeInfoById(typeId);
		if(type && value) {
			auto* func = type->GetMethodByDecl("string opAdd(const string&in) const");
			if(!func)
				func = type->GetMethodByDecl("string opAdd(const string&) const");
			if(!func)
				func = type->GetMethodByDecl("string opAdd(string&) const");
			if(!func)
				func = type->GetMethodByDecl("string opAdd_r(string&) const");
			if(func) {
				std::string val;
				std::string* ret;

				auto* ctx = engine->CreateContext();
				ctx->Prepare(func);
				ctx->SetObject(value);
				ctx->SetArgAddress(0, &val);
				auto status = ctx->Execute();
				if(status == asSUCCESS) {
					ret = (std::string*)ctx->GetReturnObject();
					s << *ret;
				}
				else {
					s << "{ " << value << " }?";
				}
			}
			else {
				// Just print the address
				s << "{ " << value << " }";
			}
		}
		else {
			// Just print the address
			s << "{ " << value << " }";
		}
	}

	return s.str();
}

};
