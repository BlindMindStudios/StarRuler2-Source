#pragma once
#include <string>
#include <functional>

namespace Loading {

void prepare(unsigned threads, std::function<void(void)> threadPrep, std::function<void(void)> threadExit);
void finalize();
void finish();
bool finished();

void addTask(const std::string& name, const char* depends, std::function<void(void)> execute, int threadRestriction = 0);
void process();

};
