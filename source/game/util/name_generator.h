#pragma once
#include <string>
#include <map>
#include <unordered_map>
#include <vector>
#include <set>

//Second order markov chain name generator
class NameGenerator {
public:
	struct ProbData {
		int occurances;
		std::unordered_map<int, int> nextCount;
	};

	std::map<std::pair<int,int>,ProbData> data;
	std::vector<std::string> names;
	std::map<std::pair<int,int>,int> nameStarts;
	std::set<std::string> usedNames;
	float mutationChance;
	bool useGeneration;
	bool preventDuplicates;

	NameGenerator();
	void clear();

	void read(const std::string& filename);
	void write(const std::string& filename);

	bool hasName(const std::string& name);
	void addName(const std::string& name);
	void addAssociation(int first, int second, int next);
	unsigned getNameCount();

	std::string generate();
};
