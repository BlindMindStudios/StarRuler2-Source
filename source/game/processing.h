#pragma once
#include <vector>

class Empire;

namespace processing {

//#define PROFILE_PROCESSING
#ifdef PROFILE_PROCESSING
struct ProcessingData {
	std::vector<double> objTime;
	std::vector<int> objCount;
	double syncTimer;

	int globalCount;
	double switchedTime;
	int switchedCount;
	double targUpdateTime;
	int targetUpdates;

	void measureType(int type, double time, int amount);

	ProcessingData();
	void clear();
};

void printProcessingProfile();
#endif

class Action {
public:
	virtual bool run() = 0;
	virtual ~Action() {}
};

void queueAction(Action* action);
void queueIsolationAction(Action* action);
void run(bool onlyActions = false);
void runIsolation();
void pauseMessageHandling();
void resumeMessageHandling();

void startEmpireThread(Empire* emp);
void start(unsigned threads);
void end();
void clear();
bool isRunning();

void pause();
void resume();

};
