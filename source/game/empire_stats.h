#pragma once
#include <string>

unsigned getEmpireStatCount();

std::string getEmpireStatName(unsigned id);
unsigned getStatID(const std::string& name);
bool statIsint(unsigned id);

void clearEmpireStats();
void loadEmpireStats(const std::string& filename);