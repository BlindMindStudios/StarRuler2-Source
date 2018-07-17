#pragma once
#include <vector>
#include <string>

class BBCode {
public:
	struct Tag {
		int type;
		int value;
		std::string name;
		std::string argument;

		std::vector<Tag> contents;

		Tag() : type(0), value(0) {
		}
	};

	Tag root;
	void parse(const std::string& content);
	void clear();

	BBCode();
	~BBCode();
};
