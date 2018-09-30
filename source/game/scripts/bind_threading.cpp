#include "scripts/binds.h"
#include "threads.h"
#include "util/refcount.h"
#include "context_cache.h"
#include "main/references.h"

#include "../source/as_scriptengine.h"
#include "../source/as_scriptobject.h"

extern void initNewThread();
extern void cleanupThread();

namespace scripts {

using namespace threads;

class refAtomic : public atomic_int {
	mutable atomic_int refcount;
public:
	refAtomic(int val) : atomic_int(val), refcount(1) {}

	void grab() const {
		++refcount;
	}

	void drop() const {
		if(--refcount == 0)
			delete this;
	}

	refAtomic& operator=(int value) {
		atomic_int::operator=(value);
		return *this;
	}

	int postInc() {
		return (*this)++;
	}

	int postDec() {
		return (*this)--;
	}
};

refAtomic* makeAtomic(int val) {
	return new refAtomic(val);
}

class refMutex : public Mutex {
	mutable atomic_int refcount;
public:
	refMutex() : refcount(1) {}

	void grab() const {
		++refcount;
	}

	void drop() const {
		if(--refcount == 0)
			delete this;
	}
};

refMutex* makeMutex() {
	return new refMutex();
}

refMutex* lockMutex(refMutex* mutex) {
	mutex->lock();
	return mutex;
}

void unlockMutex(refMutex* mutex) {
	mutex->release();
}

class refRWMutex : public ReadWriteMutex {
	mutable atomic_int refcount;
public:
	refRWMutex() : refcount(1) {}

	void grab() const {
		++refcount;
	}

	void drop() const {
		if(--refcount == 0)
			delete this;
	}
};

refRWMutex* makeRWMutex() {
	return new refRWMutex();
}

refRWMutex* lockReadMutex(refRWMutex* mutex) {
	mutex->readLock();
	return mutex;
}

refRWMutex* lockWriteMutex(refRWMutex* mutex) {
	mutex->writeLock();
	return mutex;
}

void unlockRWMutex(refRWMutex* mutex) {
	mutex->release();
}

class refSignal : public Signal {
	mutable atomic_int refcount;
public:
	refSignal() : refcount(1) {}

	void grab() const {
		++refcount;
	}

	void drop() const {
		if(--refcount == 0)
			delete this;
	}
};

refSignal* makeSignal() {
	return new refSignal();
}

bool validateThreadLocal(asITypeInfo* ot, bool& dontGarbageCollect) {
	int typeId = ot->GetSubTypeId();
	if(typeId == asTYPEID_VOID)
		return false;

	if((typeId & asTYPEID_MASK_OBJECT) && !(typeId & asTYPEID_OBJHANDLE)) {
		asITypeInfo *st = ot->GetEngine()->GetTypeInfoById(typeId);
		int flags = st->GetFlags();

		if(flags & asOBJ_REF) {
			if( !(flags & asOBJ_GC) )
				dontGarbageCollect = true;

			for(unsigned i = 0; i < st->GetFactoryCount(); ++i) {
				asIScriptFunction *func = st->GetFactoryByIndex(i);
				if(func->GetParamCount() == 0)
					return true;
			}	
			return false;
		}
		else if((flags & asOBJ_VALUE) && !(flags & asOBJ_POD))
		{
			dontGarbageCollect = true;

			for(unsigned i = 0; i < st->GetBehaviourCount(); ++i) {
				asEBehaviours beh;
				asIScriptFunction *func = st->GetBehaviourByIndex(i, &beh);
				if(beh != asBEHAVE_CONSTRUCT) continue;

				if(func->GetParamCount() == 0)
					return true;
			}
			return false;
		}
	}

	if( !(typeId & asTYPEID_OBJHANDLE) )
		dontGarbageCollect = true;

	return true;
}

static void* zeroPtr = 0;
class refThreadLocal : public AtomicRefCounted {
	threadlocalPointer<void*> ptr;
	asITypeInfo* objType;
public:
	refThreadLocal(asITypeInfo* ot)
		: objType(ot) {
	}

	~refThreadLocal() {
		int typeId = objType->GetSubTypeId();
		void* p = ptr.get();
		if(!p)
			return;

		//Free the object
		if(typeId & asTYPEID_OBJHANDLE) {
			//Release the object we have a handle to
			void* cur = *(void**)p;
			if(cur)
				objType->GetEngine()->ReleaseScriptObject(cur, objType->GetSubType());

			//Free the actual pointer
			free(p);
		}
		else if(typeId & ~asTYPEID_MASK_SEQNBR) {
			//Free the object being pointed to
			objType->GetEngine()->ReleaseScriptObject(p, objType->GetSubType());
		}
		else {
			//Free the actual pointer
			free(p);
		}
	}

	void* get() {
		void* p = ptr.get();
		int typeId = objType->GetSubTypeId();

		if(typeId & asTYPEID_OBJHANDLE) {
			//Return the pointer to the pointer,
			//which is the handle
			if(p)
				return p;
			else
				return set(&zeroPtr);
		}
		else {
			if(p)
				return p;
			else
				return set(zeroPtr);
		}
	}

	void* set(void* v) {
		void* p = ptr.get();
		int typeId = objType->GetSubTypeId();

		if(typeId & asTYPEID_OBJHANDLE) {
			if(!p) {
				p = malloc(sizeof(void*));
				*(void**)p = 0;
				ptr.set(p);
			}
			void* cur = *(void**)p;
			void* next = *(void**)v;

			*(void**)p = next;

			if(next)
				objType->GetEngine()->AddRefScriptObject(next, objType->GetSubType());
			if(cur)
				objType->GetEngine()->ReleaseScriptObject(cur, objType->GetSubType());
			return p;
		}
		else if(typeId & ~asTYPEID_MASK_SEQNBR) {
			if(!p) {
				p = (void*)objType->GetEngine()->CreateScriptObject(objType);
				ptr.set(p);
			}

			if(v)
				objType->GetEngine()->AssignScriptObject(p, v, objType);
			return p;
		}
		else if(typeId == asTYPEID_BOOL ||
				typeId == asTYPEID_INT8 ||
				typeId == asTYPEID_UINT8) {
			if(!p) {
				p = malloc(sizeof(char));
				*(char*)p = 0;
				ptr.set(p);
			}
			if(v)
				*(char*)p = *(char*)v;
			return p;
		}
		else if(typeId == asTYPEID_INT16 ||
				typeId == asTYPEID_UINT16) {
			if(!p) {
				p = malloc(sizeof(short));
				*(short*)p = 0;
				ptr.set(p);
			}
			if(v)
				*(short*)p = *(short*)v;
			return p;
		}
		else if(typeId == asTYPEID_INT32 ||
				typeId == asTYPEID_UINT32 ||
				typeId == asTYPEID_FLOAT ||
				typeId > asTYPEID_DOUBLE) /*enums*/ {
			if(!p) {
				p = malloc(sizeof(int));
				*(int*)p = 0;
				ptr.set(p);
			}
			if(v)
				*(int*)p = *(int*)v;
			return p;
		}
		else if(typeId == asTYPEID_INT64 ||
				 typeId == asTYPEID_UINT64 ||
				 typeId == asTYPEID_DOUBLE) {
			if(!p) {
				p = malloc(sizeof(double));
				*(double*)p = 0;
				ptr.set(p);
			}
			if(v)
				*(double*)p = *(double*)v;
			return p;
		}
		return 0;
	}
};

refThreadLocal* createThreadLocal(asITypeInfo* ot) {
	return new refThreadLocal(ot);
}

threads::threadreturn threadcall runScriptThread(void* arg);

bool IsHandleCompatibleWithObject(asCScriptEngine* engine, void *obj, int objTypeId, int handleTypeId)
{
	// if equal, then it is obvious they are compatible
	if( objTypeId == handleTypeId )
		return true;

	// Get the actual data types from the type ids
	asCDataType objDt = engine->GetDataTypeFromTypeId(objTypeId);
	asCDataType hdlDt = engine->GetDataTypeFromTypeId(handleTypeId);

	// A handle to const cannot be passed to a handle that is not referencing a const object
	if( objDt.IsHandleToConst() && !hdlDt.IsHandleToConst() )
		return false;

	if( objDt.GetTypeInfo() == hdlDt.GetTypeInfo() )
	{
		// The object type is equal
		return true;
	}
	else if( objDt.IsScriptObject() && obj )
	{
		// Get the true type from the object instance
		asITypeInfo *objType = ((asCScriptObject*)obj)->GetObjectType();

		// Check if the object implements the interface, or derives from the base class
		// This will also return true, if the requested handle type is an exact match for the object type
		if( objType->Implements(hdlDt.GetTypeInfo()) ||
			objType->DerivesFrom(hdlDt.GetTypeInfo()) )
			return true;
	}

	return false;
}

struct ScriptThread {
	//Two reference counters, one for the resource, one for the scripts
	// When the script counter reaches 0, one system reference is lost, and the thread is shut down at the next opportunity
	// When the system counter reaches 0, this struct is deleted
	threads::atomic_int systemRefs, scriptRefs;
	bool gcFlag;

	threads::atomic_int runThread;
	bool wasError;

	Manager* manager;
	asIScriptEngine* engine;
	asIScriptFunction* function;

	threads::Mutex objLock;
	void* object;
	asITypeInfo* objType;

	bool setScriptObject(void* pointer, int typeID) {
		threads::Lock lock(objLock);
		if(typeID == 0 || pointer == 0 || *(void**)pointer == 0) {
			if(object != 0) {
				engine->ReleaseScriptObject(object, objType);
				object = 0;
			}
			return true;
		}
		else if(typeID & asTYPEID_OBJHANDLE) {
			object = *(void**)pointer;
			objType = engine->GetTypeInfoById(typeID);
			engine->AddRefScriptObject(object, objType);
			return true;
		}
		return false;
	}

	bool getScriptObject(void* pointer, int typeID) {
		if(pointer == 0)
			return false;

		threads::Lock lock(objLock);
		if(typeID & asTYPEID_OBJHANDLE) {
			if(typeID & asTYPEID_MASK_OBJECT && IsHandleCompatibleWithObject((asCScriptEngine*)engine, object, objType->GetTypeId(), typeID)) {
				engine->AddRefScriptObject(object, objType);
				*(void**)pointer = object;
				return true;
			}
		}
		return false;
	}

	void stop() {
		std::int32_t comparand = 2;
		runThread.compare_exchange_strong(comparand, 1);
	}

	bool start(const std::string& func) {
		asIScriptContext* ctx = asGetActiveContext();
		if(engine != ctx->GetEngine())
			return false;

		Manager* localMan = &Manager::fromEngine(engine);
		if(!localMan)
			return false;

		asIScriptFunction* localFunc = localMan->getFunction(func, "(double, ScriptThread&)", "double");

		if(localFunc) {
			std::int32_t comparand = 0;
			if(runThread.compare_exchange_strong(comparand, 2)) {
				function = localFunc;
				manager = localMan;
				++systemRefs;

				wasError = false;
				threads::createThread(runScriptThread, this);
				return true;
			}
		}

		return false;
	}

	bool isRunning() const {
		return runThread != 0;
	}

	ScriptThread() : runThread(false), systemRefs(1), scriptRefs(1), gcFlag(false), engine(asGetActiveContext()->GetEngine()), function(0), object(0), wasError(false) {
		engine->NotifyGarbageCollectorOfNewObject(this, engine->GetTypeInfoByName("ScriptThread"));
	}

	ScriptThread(const std::string& func) : runThread(false), systemRefs(1), scriptRefs(1), gcFlag(false), engine(asGetActiveContext()->GetEngine()), function(0), object(0), wasError(false) {
		engine->NotifyGarbageCollectorOfNewObject(this, engine->GetTypeInfoByName("ScriptThread"));
		start(func);
	}

	ScriptThread(const std::string& func, void* pointer, int typeID) : runThread(false), systemRefs(1), scriptRefs(1), gcFlag(false), engine(asGetActiveContext()->GetEngine()), function(0), object(0), wasError(false) {
		engine->NotifyGarbageCollectorOfNewObject(this, engine->GetTypeInfoByName("ScriptThread"));
		setScriptObject(pointer, typeID);
		start(func);
	}

	static ScriptThread* create() {
		return new ScriptThread();
	}

	static ScriptThread* create_f(const std::string& func) {
		return new ScriptThread(func);
	}

	static ScriptThread* create_fo(const std::string& func, void* pointer, int typeID) {
		return new ScriptThread(func, pointer, typeID);
	}

	void systemDrop() {
		if(--systemRefs == 0)
			delete this;
	}

	void scriptGrab() {
		gcFlag = false;
		++scriptRefs;
	}

	void scriptDrop() {
		gcFlag = false;
		if(--scriptRefs == 0) {
			runThread = 0;
			systemDrop();
		}
	}

	void setGCFlag() {
		gcFlag = true;
	}

	bool getGCFlag() const {
		return gcFlag;
	}

	int getRefcount() const {
		return scriptRefs;
	}

	void enumRefs(asIScriptEngine* eng) {
		objLock.lock();
		if(object)
			eng->GCEnumCallback(object);
		objLock.release();
	}

	void releaseRefs(asIScriptEngine* eng) {
		setScriptObject(0,0);
	}
};

threads::threadreturn threadcall runScriptThread(void* arg) {
	ScriptThread& thread = *(ScriptThread*)arg;
	initNewThread();

	//Server uses game time, client and menu use frame time
	bool useGameTime = thread.engine != devices.scripts.client->engine && thread.engine != devices.scripts.menu->engine;
	
	double curTime = useGameTime ? devices.driver->getGameTime() : devices.driver->getFrameTime();
	double lastTime = curTime;
	double nextTime = lastTime;
	thread.manager->scriptThreadCreate();
	
	while(thread.runThread == 2) {
		if(!thread.manager->scriptThreadStart())
			break;
		curTime = useGameTime ? devices.driver->getGameTime() : devices.driver->getFrameTime();

		if(curTime >= nextTime) {
			double delta = curTime - lastTime;
			lastTime = curTime;

#ifdef TRACE_GC_LOCK
			thread.manager->markGCImpossible();
#endif

			auto call = thread.manager->call(thread.function);
			call.push(delta);
			call.push(arg);

			double delay = 1.0;
			if(!call.call(delay)) {
#ifdef TRACE_GC_LOCK
				thread.manager->markGCPossible();
#endif
				thread.wasError = true;
				thread.runThread = 0;
				thread.manager->scriptThreadEnd();
				break;
			}

#ifdef TRACE_GC_LOCK
			thread.manager->markGCPossible();
#endif
			nextTime = curTime + delay;
		}

		thread.manager->scriptThreadEnd();
		//Sleep until 2ms before the next timer
		if(devices.driver->getGameSpeed() < 0.01)
			threads::idle();
		else {
			int sleepTime = (1000.0 * (nextTime - curTime)) - 2.0;
			if(sleepTime < 0)
				sleepTime = 0;
			threads::sleep((unsigned)sleepTime);
		}
	}

	cleanupThread();
	thread.manager->scriptThreadDestroy();
	thread.systemDrop();
	thread.runThread = 0;
	return 0;
}

void RegisterThreadingBinds() {

	//Register atomic integer
	ClassBind aint("atomic_int", asOBJ_REF, 0);
	aint.addFactory("atomic_int@ f(int)", asFUNCTION(makeAtomic));
	aint.setReferenceFuncs(asMETHOD(refAtomic, grab), asMETHOD(refAtomic, drop));
	aint.addMethod("int opPreInc()", asMETHODPR(refAtomic, operator++, (), int));
	aint.addMethod("int opPostInc()", asMETHOD(refAtomic, postInc));
	aint.addMethod("int opPreDec()", asMETHODPR(refAtomic, operator--, (), int));
	aint.addMethod("int opPostDec()", asMETHOD(refAtomic, postDec));
	aint.addMethod("atomic_int& opAssign(int)", asMETHODPR(refAtomic, operator=, (int), refAtomic&));
	aint.addMethod("void opAddAssign(int)", asMETHODPR(refAtomic, operator+=, (int), int));
	aint.addMethod("void opDecAssign(int)", asMETHODPR(refAtomic, operator-=, (int), int));
	aint.addMethod("atomic_int& set(int)", asMETHODPR(refAtomic, operator=, (int), refAtomic&));
	aint.addMethod("int get()", asMETHODPR(refAtomic, get, () const, int));
	aint.addMethod("int get_value()", asMETHODPR(refAtomic, get_basic, (), int));
	aint.addMethod("void set_value(int)", asMETHODPR(refAtomic, set_basic, (int), void));

	//Register regular mutex and lock
	ClassBind mutex("Mutex", asOBJ_REF, 0);
	mutex.addFactory("Mutex@ f()", asFUNCTION(makeMutex));
	mutex.setReferenceFuncs(asMETHOD(refMutex, grab), asMETHOD(refMutex, drop));

	ClassBind lock("Lock", asOBJ_REF | asOBJ_SCOPED, 0);
	lock.addFactory("Lock@ f(Mutex&)", asFUNCTION(lockMutex));
	lock.addExternBehaviour(asBEHAVE_RELEASE, "void f()", asFUNCTION(unlockMutex));

	//Register read-write mutex and lock
	ClassBind rw_mutex("ReadWriteMutex", asOBJ_REF, 0);
	rw_mutex.addFactory("ReadWriteMutex@ f()", asFUNCTION(makeRWMutex));
	rw_mutex.setReferenceFuncs(asMETHOD(refRWMutex, grab), asMETHOD(refRWMutex, drop));

	ClassBind readLock("ReadLock", asOBJ_REF | asOBJ_SCOPED, 0);
	readLock.addFactory("ReadLock@ f(ReadWriteMutex&)", asFUNCTION(lockReadMutex));
	readLock.addExternBehaviour(asBEHAVE_RELEASE, "void f()", asFUNCTION(unlockRWMutex));

	ClassBind writeLock("WriteLock", asOBJ_REF | asOBJ_SCOPED, 0);
	writeLock.addFactory("WriteLock@ f(ReadWriteMutex&)", asFUNCTION(lockWriteMutex));
	writeLock.addExternBehaviour(asBEHAVE_RELEASE, "void f()", asFUNCTION(unlockRWMutex));

	//Register signal
	ClassBind signal("Signal", asOBJ_REF, 0);
	signal.addFactory("Signal@ f()", asFUNCTION(makeSignal));
	signal.setReferenceFuncs(asMETHOD(refSignal, grab), asMETHOD(refSignal, drop));
	signal.addMethod("void signal(int)", asMETHOD(refSignal, signal));
	signal.addMethod("void signalDown()", asMETHOD(refSignal, signalDown));
	signal.addMethod("void signalUp()", asMETHOD(refSignal, signalUp));
	signal.addMethod("bool check(int)", asMETHOD(refSignal, check));
	signal.addMethod("void wait(int)", asMETHOD(refSignal, wait));
	signal.addMethod("void waitNot(int)", asMETHOD(refSignal, waitNot));
	signal.addMethod("void waitAndSignal(int, int)", asMETHOD(refSignal, waitAndSignal));

	//General threading functions
	bind("void sleep(uint ms)", asFUNCTION(threads::sleep))
		doc("Stops thread processing for some number of milliseconds.",
			"Number of milliseconds to sleep (approximately)");
	bind("int get_threadID()", asFUNCTION(getThreadID));

	//Thread local storage
	ClassBind tl("ThreadLocal", asOBJ_REF | asOBJ_TEMPLATE);
	tl.addLooseBehaviour(asBEHAVE_TEMPLATE_CALLBACK, "bool f(int&in,bool&out)", asFUNCTION(validateThreadLocal));
	tl.setReferenceFuncs(asMETHOD(refThreadLocal, grab), asMETHOD(refThreadLocal, drop));
	tl.addFactory("ThreadLocal<T>@ f(int&in)", asFUNCTION(createThreadLocal));
	tl.addMethod("T& get()", asMETHOD(refThreadLocal, get));
	tl.addMethod("T& set(const T&in)", asMETHOD(refThreadLocal, set));

	//Thread management
	ClassBind thread("ScriptThread", asOBJ_REF | asOBJ_GC);
	classdoc(thread, "Creates and controls script threads.");

	thread.setReferenceFuncs(asMETHOD(ScriptThread,scriptGrab), asMETHOD(ScriptThread,scriptDrop));
	thread.addGarbageCollection(
			asMETHOD(ScriptThread,setGCFlag),
			asMETHOD(ScriptThread,getGCFlag),
			asMETHOD(ScriptThread,getRefcount),
			asMETHOD(ScriptThread,enumRefs),
			asMETHOD(ScriptThread,releaseRefs) );

	thread.addFactory("ScriptThread@ f()", asFUNCTION(ScriptThread::create));
	thread.addFactory("ScriptThread@ f(const string &in entry)", asFUNCTION(ScriptThread::create_f))
		doc("Starts a thread using the specified function.",
			"Entry point of type 'double f(double, ScriptThread&)'. Receives time since last call and a reference to the associated ScripThread. Returns delay till next call.", "");
	thread.addFactory("ScriptThread@ f(const string &in entry, ?&in)", asFUNCTION(ScriptThread::create_fo))
		doc("Starts a thread using the specified function and script object.",
			"Entry point of type 'double f(double, ScriptThread&)'. Receives time since last call and a reference to the associated ScripThread. Returns delay till next call.", "Script object to assign to thread.", "");
	thread.addMethod("bool start(const string &in entry)", asMETHOD(ScriptThread,start))
		doc("Starts a thread using the specified function.",
			"Entry point of type 'double f(double, ScriptThread&)'. Receives time since last call and a reference to the associated ScripThread. Returns delay till next call.", "True if the thread was started");
	thread.addMethod("void stop()", asMETHOD(ScriptThread,stop))
		doc("Stops the active thread.");
	thread.addMethod("bool get_running()", asMETHOD(ScriptThread,isRunning))
		doc("", "Whether there is an active thread.");
	thread.addMethod("bool setObject(?&)", asMETHOD(ScriptThread,setScriptObject))
		doc("Sets the thread's object. Can only receive script object handles.", "", "True if the reference could be taken");
	thread.addMethod("bool getObject(?&out)", asMETHOD(ScriptThread,getScriptObject))
		doc("Gets the thread's object. Can only receive script object handles.", "", "True if the reference could be stored");
	thread.addMember("bool wasError", offsetof(ScriptThread,wasError))
		doc("Whether the thread was ended due to an error.");
}
	
};
