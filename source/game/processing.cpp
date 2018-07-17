#include "processing.h"
#include "main/references.h"
#include "threads.h"
#include "main/initialization.h"
#include "main/logging.h"
#include "util/random.h"
#include "scripts/context_cache.h"
#include "obj/lock.h"
#include "design/projectiles.h"
#include "empire.h"
#include <deque>

extern threads::atomic_int remainingEmpireMessages;

namespace processing {
	
threads::threadreturn threadcall process(void* data);
threads::threadreturn threadcall messageProcess(void* data);
threads::threadreturn threadcall empireMessageProcess(void* data);

int threadCount = 0;
bool stopProcessing = false, pauseProcessing = false, pauseMessageHandlers = false;
threads::Signal threadsActive, msgHandlersActive;

threads::Mutex actionLock;
std::deque<Action*> process_queue;

std::vector<Action*> isolation_queue;

#ifdef PROFILE_PROCESSING
Threaded(ProcessingData*) threadProc;
#endif

unsigned idleObjectTickCount = 25, activeObjectTickCount = 300;

void queueAction(Action* action) {
	actionLock.lock();
	process_queue.push_back(action);
	actionLock.release();
}

void queueIsolationAction(Action* action) {
	actionLock.lock();
	isolation_queue.push_back(action);
	actionLock.release();
}

void runIsolation() {
	if(isolation_queue.empty())
		return;
	processing::pause();
	actionLock.lock();
	foreach(it, isolation_queue) {
		(*it)->run();
		delete *it;
	}
	isolation_queue.clear();
	actionLock.release();
	processing::resume();
}

Action* popAction() {
	if(process_queue.empty())
		return 0;
	actionLock.lock();
	Action* action = 0;
	if(!process_queue.empty()) {
		action = process_queue.back();
		process_queue.pop_back();
	}
	actionLock.release();
	return action;
}

void start(unsigned threads) {
#ifdef PROFILE_PROCESSING
	if(!threadProc)
		threadProc = new ProcessingData();
#endif

	stopProcessing = false;
	threadCount = threads;
	threadsActive.signal(threads);
	msgHandlersActive.signal(threads);
	for(unsigned i = 0; i < threads; ++i) {
#ifdef PROFILE_PROCESSING
		threads::createThread(process, new ProcessingData());
#else
		threads::createThread(process, nullptr);
#endif
		threads::createThread(messageProcess, nullptr);
	}
}

void end() {
	stopProcessing = true;
	threadsActive.wait(0);
	msgHandlersActive.wait(0);
}

bool isRunning() {
	return !threadsActive.check(0);
}

void clear() {
	if(devices.scripts.cache_server)
		devices.scripts.cache_server->clearScriptThreads();
	if(devices.scripts.cache_shadow)
		devices.scripts.cache_shadow->clearScriptThreads();
	if(devices.scripts.client)
		devices.scripts.client->clearScriptThreads();
	foreach(it, process_queue)
		delete *it;
	process_queue.clear();
}

void pause() {
	pauseProjectiles();
	if(devices.scripts.cache_server)
		devices.scripts.cache_server->pauseScriptThreads();
	if(devices.scripts.cache_shadow)
		devices.scripts.cache_shadow->pauseScriptThreads();
	if(devices.scripts.client)
		devices.scripts.client->pauseScriptThreads();
	pauseProcessing = true;
	threadsActive.wait(0);
	while(hasRemainingMessages())
		threads::idle();
	pauseMessageHandlers = true;
	while(hasRemainingMessages())
		threads::idle();
	msgHandlersActive.wait(0);
}

void resume() {
	pauseProcessing = false;
	pauseMessageHandlers = false;
	if(stopProcessing)
		return;
	threadsActive.waitNot(0);
	msgHandlersActive.waitNot(0);
	if(devices.scripts.cache_server)
		devices.scripts.cache_server->resumeScriptThreads();
	if(devices.scripts.cache_shadow)
		devices.scripts.cache_shadow->resumeScriptThreads();
	if(devices.scripts.client)
		devices.scripts.client->resumeScriptThreads();
	resumeProjectiles();
}

void pauseMessageHandling() {
	pauseMessageHandlers = true;
	while(hasRemainingMessages())
		threads::idle();
	msgHandlersActive.wait(0);
}

void resumeMessageHandling() {
	pauseMessageHandlers = false;
}

#ifdef PROFILE_PROCESSING
threads::atomic_int printProcProfile;

void printProcessingProfile() {
	printProcProfile = threadCount + 1;
}

ProcessingData::ProcessingData() {
	syncTimer = 0;
	clear();
}

void ProcessingData::clear() {
	for(unsigned i = 0, cnt = objTime.size(); i < cnt; ++i) {
		objTime[i] = 0;
		objCount[i] = 0;
	}

	globalCount = 0;
	switchedTime = 0;
	targUpdateTime = 0;
	switchedCount = 0;
	targetUpdates = 0;
}

void ProcessingData::measureType(int type, double time, int amount) {
	if(objTime.size() <= type) {
		objTime.resize(type+1, 0);
		objCount.resize(type+1, 0);
	}

	objTime[type] += time;
	objCount[type] += amount;
}

void profileProcessing() {
	double curTime = devices.driver->getAccurateTime();
	if(curTime >= threadProc->syncTimer) {
		if(printProcProfile > 0) {

			print("Thread %d Processing Profile:", threads::getThreadID());
			for(unsigned i = 0, cnt = threadProc->objTime.size(); i < cnt; ++i) {
				if(threadProc->objCount[i] == 0)
					continue;
				print("    %s: %d objects in %.4gms (~%.3gms per)",
					getScriptObjectType(i)->name.c_str(),
					threadProc->objCount[i],
					threadProc->objTime[i] * 1000.0,
					(threadProc->objTime[i] / threadProc->objCount[i]) * 1000.0);
			}
			if(threadProc->globalCount != 0) {
				print("    Global processing: %d ticks", threadProc->globalCount);
				if(threadProc->switchedCount != 0)
					print("        Switched objects: %d objects in %.4gms (~%.3gms per)",
						threadProc->switchedCount, threadProc->switchedTime * 1000.0,
						(threadProc->switchedTime / threadProc->switchedCount) * 1000.0);
				if(threadProc->targetUpdates != 0)
					print("        Target Update: %d updates in %.4gms (~%.3gms per)",
						threadProc->targetUpdates, threadProc->targUpdateTime * 1000.0,
						threadProc->targUpdateTime * 1000.0 / threadProc->targetUpdates);
			}

			--printProcProfile;
		}

		threadProc->clear();
		threadProc->syncTimer = curTime + 1.0;
	}
}
#endif

void run(bool onlyActions) {
	Action* cur_action = popAction();
	if(cur_action) {
		if(cur_action->run())
			delete cur_action;
		else
			queueAction(cur_action);
	}
	else if(!onlyActions) {
		double time = devices.driver->getGameTime();
		tickRandomLock(time, idleObjectTickCount);
	}

#ifdef PROFILE_PROCESSING
	profileProcessing();
#endif
}

threads::threadreturn threadcall messageProcess(void* data) {
	enterSection(NS_MessageThread);
	initNewThread();

	while(!stopProcessing) {
		if(hasRemainingMessages()) {
			tickRandomMessages(5);
			threads::sleep(0);
		}
		else {
			if(pauseMessageHandlers) {
				msgHandlersActive.signalDown();
				while(pauseMessageHandlers && !hasRemainingMessages())
					threads::sleep(1);
				msgHandlersActive.signalUp();
			}
			else {
				threads::idle();
			}
		}
	}

	cleanupThread();
	msgHandlersActive.signalDown();
	return 0;
}

void startEmpireThread(Empire* emp) {
	msgHandlersActive.signalUp();
	threads::createThread(empireMessageProcess, emp);
}

threads::atomic_int nextEmpTickIndex;
threads::threadreturn threadcall empireMessageProcess(void* data) {
	enterSection(NS_MessageThread);
	Empire* emp = (Empire*)data;
	initNewThread();

	while(!stopProcessing) {
		if(hasRemainingMessages()) {
			if(!emp->messages.empty()) {
				emp->processMessages();
			}
			else {
				threads::sleep(1);
			}
		}
		else {
			if(pauseMessageHandlers) {
				msgHandlersActive.signalDown();
				while(pauseMessageHandlers && !hasRemainingMessages())
					threads::sleep(1);
				msgHandlersActive.signalUp();
			}
			else {
				threads::idle();
			}
		}
	}

	cleanupThread();
	msgHandlersActive.signalDown();
	return 0;
}

threads::threadreturn threadcall process(void* data) {
	enterSection(NS_Processing);
#ifdef PROFILE_PROCESSING
	threadProc = (ProcessingData*)data;
#endif
	initNewThread();

	while(!stopProcessing) {
		if(pauseProcessing) {
			while(hasRemainingMessages() || hasQueuedChildren()) {
				acquireRandomChildren();
				tickRandomMessages();
				threads::idle();
			}
			threadsActive.signalDown();
			while(pauseProcessing)
				threads::sleep(1);
			threadsActive.signalUp();
		}

		Action* cur_action = popAction();
		if(cur_action) {
			if(cur_action->run()) {
				delete cur_action;
				threads::sleep(0);
				continue;
			}
			else {
				queueAction(cur_action);
			}
		}

		double time = devices.driver->getGameTime();

		tickRandomMessages();
		tickRandomLock(time, activeObjectTickCount);

		threads::idle();

#ifdef PROFILE_PROCESSING
		profileProcessing();
#endif
	}

	cleanupThread();
	threadsActive.signalDown();

	return 0;
}

};
