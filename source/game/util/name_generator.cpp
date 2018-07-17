#include "name_generator.h"
#include "compat/misc.h"
#include "str_util.h"
#include "util/random.h"
#include <fstream>

#ifndef NAMEGEN_MUTATE_END_PCT
#define NAMEGEN_MUTATE_END_PCT 0.1
#endif

NameGenerator::NameGenerator() {
	clear();
}

void NameGenerator::clear() {
	data.clear();
	names.clear();
	nameStarts.clear();
	usedNames.clear();
	preventDuplicates = false;
	useGeneration = true;
	mutationChance = 0;
}

void NameGenerator::read(const std::string& filename) {
	std::ifstream file(filename);
	skipBOM(file);
	if(file.is_open()) {
		while(true) {
			std::string line;
			std::getline(file, line);
			if(file.fail())
				break;
			line = trim(line);
			if(line.size() > 0)
				addName(line);
		}
	}
}

void NameGenerator::write(const std::string& filename) {
	std::ofstream file(filename);
	foreach(it, names)
		file << *it << "\n";
}

static int randomchar(bool start = false) {
	if(start) {
		return randomi((int)'A', (int)'Z');
	}
	else {
		if(randomf() < NAMEGEN_MUTATE_END_PCT)
			return 0;
		return randomi((int)'a', (int)'z');
	}
}

std::string NameGenerator::generate() {
	if(names.size() == 0)
		return "Error";
	if(!useGeneration)
		return names[randomi(0, names.size() - 1)];

	std::string name;

	while(true) {
		std::pair<int, int> syl;
		name = "";

		//Add the start of a name
		if(mutationChance != 0 && randomf() < mutationChance) {
			syl.first = randomchar(true);
			syl.second = randomchar();
			u8append(name, syl.first);
			u8append(name, syl.second);
		}
		else {
			int chance = randomi(0, names.size() - 1);
			int cum = 0;
			foreach(it, nameStarts) {
				cum += it->second;
				if(chance < cum) {
					syl.first = it->first.first;
					syl.second = it->first.second;
					u8append(name, syl.first);
					u8append(name, syl.second);
					break;
				}
			}
		}

		//Continue on
		int next = 0;
		do {
			auto it = data.find(syl);
			if(it == data.end())
				break;
			ProbData& pd = it->second;

			if(mutationChance != 0 && randomf() < mutationChance) {
				next = randomchar();
				syl.first = syl.second;
				syl.second = next;
				if(next)
					u8append(name, next);
			}
			else {
				int chance = randomi(0, pd.occurances - 1);
				int cum = 0;
				foreach(it, pd.nextCount) {
					cum += it->second;
					if(chance < cum) {
						next = it->first;
						syl.first = syl.second;
						syl.second = next;
						if(next)
							u8append(name, next);
						break;
					}
				}
			}
		} while(next);

		//Do duplicate prevention
		if(!preventDuplicates)
			return name;

		if(usedNames.find(name) == usedNames.end()) {
			usedNames.insert(name);
			return name;
		}
	}
}

bool NameGenerator::hasName(const std::string& name) {
	foreach(it, names)
		if(*it == name)
			return true;
	return false;
}

unsigned NameGenerator::getNameCount() {
	return names.size();
}

void NameGenerator::addName(const std::string& name) {
	u8it it(name);

	//Add start of word
	std::pair<int,int> syl;
	syl.first = it++;
	if(!syl.first)
		return;
	syl.second = it++;
	if(!syl.second)
		return;
	int next = it++;
	if(!next)
		return;

	names.push_back(name);
	auto f = nameStarts.find(syl);
	if(f == nameStarts.end())
		nameStarts[syl] = 1;
	else
		nameStarts[syl]++;

	//Add association for lowercase
	if(syl.first >= 'A' && syl.first <= 'Z')
		addAssociation(syl.first-'A'+'a', syl.second, next);

	//Add all the syllables
	while(next) {
		addAssociation(syl.first, syl.second, next);

		syl.first = syl.second;
		syl.second = next;
		next = it++;
	}

	addAssociation(syl.first, syl.second, next);
}

void NameGenerator::addAssociation(int first, int second, int next) {
	std::pair<int,int> syl;
	syl.first = first;
	syl.second = second;

	ProbData* pd = 0;
	auto it = data.find(syl);
	if(it == data.end()) {
		ProbData newData;
		newData.occurances = 0;
		data.insert(std::pair<std::pair<int,int>,ProbData>(syl, newData));
		pd = &data[syl];
	}
	else {
		pd = &it->second;
	}

	pd->occurances += 1;
	auto f = pd->nextCount.find(next);
	if(f == pd->nextCount.end())
		pd->nextCount[next] = 1;
	else
		pd->nextCount[next]++;
}
