#include "threaded_loader.h"
#include "threads.h"
#include <unordered_map>
#include <set>
#include <list>
#include "main/references.h"
#include "main/logging.h"

namespace Loading {

struct Task;
std::function<void(void)> threadSetup, threadCleanup;

threads::atomic_int workers(0);
bool finalized = false;
double startTime;

threads::Mutex taskLock;
threads::Signal processingTasks;
bool tasksFinished;
std::unordered_map<std::string, Task*> namedTasks;
std::list<Task*> tasks;
auto nextTask = tasks.end();

struct Task {
	std::string name;

	std::vector<Task*> dependencies;

	bool finished;
	double executionTime;

	int threadRestriction;

	std::function<void(void)> _execute;

	Task(const std::string& Name, const char* depends) : name(Name), finished(false), threadRestriction(-1) {
		while(depends && depends[0] != '\0') {
			const char* end = strchr(depends+1, ',');
			if(end == 0)
				end = strchr(depends, '\0');

			std::string dependencyName(depends, end - depends);
			if(dependencyName == name)
				throw "Cylic loading depedency";
			
			auto dependency  = namedTasks.find(dependencyName);
			if(dependency != namedTasks.end())
				dependencies.push_back(dependency->second);
			else
				throw "Missing dependency";

			depends = *end == ',' ? end+1 : end;
		}

#ifdef _DEBUG
		if(namedTasks.find(Name) != namedTasks.end())
			throw "Duplicate task";
#endif
		
		namedTasks[Name] = this;
	}

	bool mayExecute() {
		if(threadRestriction != threads::invalidThreadID && threadRestriction != threads::getThreadID())
			return false;
		for(unsigned i = 0; i < dependencies.size(); ++i)
			if(!dependencies[i]->isFinished())
				return false;
		return true;
	}

	bool isMyJob() {
		return threadRestriction == threads::getThreadID();
	}

	void execute() {
		if(isFinished())
			return;
		double start = devices.driver->getAccurateTime();
		info("%s started at %.1fs on thread %i", name.c_str(), start - startTime, threads::getThreadID());

		_execute();
		double end = devices.driver->getAccurateTime();
		executionTime = end - start;
		finished = true;

		info("%s took %.1fms on thread %i", name.c_str(), executionTime * 1000.0, threads::getThreadID());
	}

	bool isFinished() {
		return finished;
	}
};

void addTask(const std::string& name, const char* depends, std::function<void(void)> execute, int threadRestriction) {
	Task* task = new Task(name, depends);

	task->_execute = execute;
	task->threadRestriction = threadRestriction;

	taskLock.lock();
	tasks.push_back(task);
	taskLock.release();
}

bool finished() {
	return tasksFinished;
}

threads::threadreturn threadcall processLoad(void* arg) {
	if(threadSetup)
		threadSetup();

	while(!finalized || !tasks.empty()) {
		process();
		threads::sleep(1);
	}
	--workers;

	//This lets us have accurate timings, since we want
	//to know when the last task finished, not when
	//the loading period is over (ie for preloading)
	if(workers == 0) {
		processingTasks.wait(0);
		double totalTime = 0;
		auto iTask = namedTasks.begin();
		while(iTask != namedTasks.end()) {
			totalTime += iTask->second->executionTime;

			delete iTask->second;
			iTask = namedTasks.erase(iTask);
		}

		double time = devices.driver->getAccurateTime(), loadTime = time - startTime;
		print("Loaded in %.1f seconds", loadTime);
		info("Tasks used a total of %.1f seconds (%d%% faster)", totalTime, (int)(100.0*totalTime/loadTime)-100);
		tasksFinished = true;
	}

	if(threadCleanup)
		threadCleanup();
	return 0;
}

void prepare(unsigned threads, std::function<void(void)> threadPrep, std::function<void(void)> threadExit) {
	threadSetup = threadPrep;
	threadCleanup = threadExit;
	tasksFinished = false;

	startTime = devices.driver->getAccurateTime();
	workers = threads;
	for(unsigned i = 0; i < threads; ++i)
		threads::createThread(processLoad,0);
}

void finalize() {
	double time = devices.driver->getAccurateTime();
	info("Preparing tasks took %.1f ms", (time - startTime) * 1000.0);

	finalized = true;
}

void finish() {
	while(workers != 0)
		threads::sleep(0);
	finalized = false;

	nextTask = tasks.end();
}

void process() {
	processingTasks.signalUp();
	if(tasks.empty()) {
		processingTasks.signalDown();
		return;
	}

	taskLock.lock();

	Task* task = 0;
	for(auto i = tasks.begin(), end = tasks.end(); i != end; ++i) {
		Task* check = *i;
		if(check->isMyJob() && check->mayExecute()) {
			task = check;
			if(nextTask == i)
				nextTask = tasks.erase(i);
			else
				tasks.erase(i);
			break;
		}
	}

	if(task == 0) {
		while(tasks.empty() == false) {
			if(nextTask == tasks.end())
				nextTask = tasks.begin();

			Task* check = *nextTask;
			if(check->mayExecute()) {
				nextTask = tasks.erase(nextTask);
				task = check;
				break;
			}

			++nextTask;
			taskLock.release();
			threads::sleep(0);
			taskLock.lock();
		}
	}

	taskLock.release();

	if(task) {
		task->execute();
		if(!task->isFinished()) {
			taskLock.lock();
			tasks.push_back(task);
			taskLock.release();
		}
	}

	processingTasks.signalDown();
}

};
