#include "bbcode.h"

enum ParseState {
	PS_Text,
	PS_StartTag,
	PS_EndTag
};

static const char* parseTag(BBCode::Tag& root, const char* str) {
	bool escaped = false;
	bool selfClose = false;
	ParseState state = PS_Text;
	const char* start = str;
	unsigned tagDepth = 0;

	while(*str != 0) {
		unsigned char c = *str;
		switch(state) {
			case PS_Text:
				if(c == '\\') {
					if(escaped) {
						escaped = false;
						if(str != start) {
							BBCode::Tag t;
							t.type = -1;
							t.argument = std::string(start, str - start);
							root.contents.push_back(t);
						}
						++str;
						start = str;
					}
					else {
						escaped = true;
						++str;
					}
				}
				else if(c == '[') {
					if(escaped) {
						--str;
						if(str != start) {
							BBCode::Tag t;
							t.type = -1;
							t.argument = std::string(start, str - start);
							root.contents.push_back(t);
						}
						++str;

						escaped = false;
						start = str;
						++str;
					}
					else {
						if(str != start) {
							BBCode::Tag t;
							t.type = -1;
							t.argument = std::string(start, str - start);
							root.contents.push_back(t);
						}

						state = PS_StartTag;
						++str;
						start = str;
					}
				}
				else {
					++str;
				}
			break;
			case PS_StartTag:
				if(c == '/') {
					if(str == start) {
						state = PS_EndTag;
						++str;
						start = str;
					}
					else {
						selfClose = true;
						++str;
					}
				}
				else if(c == ']') {
					if(tagDepth > 0) {
						--tagDepth;
						++str;
						selfClose = true;
						break;
					}

					std::string tagname;
					if(selfClose)
						tagname = std::string(start, (str - 1) - start);
					else
						tagname = std::string(start, str - start);
					++str;

					BBCode::Tag t;
					auto argpos = tagname.find('=');
					if(argpos != std::string::npos) {
						t.name = tagname.substr(0, argpos);
						if(argpos < tagname.size() - 1)
							t.argument = tagname.substr(argpos+1);
					}
					else {
						t.name = tagname;
					}

					if(selfClose)
						selfClose = false;
					else
						str = parseTag(t, str);
					state = PS_Text;
					start = str;

					root.contents.push_back(t);
				}
				else {
					if(c == '[')
						++tagDepth;
					selfClose = false;
					++str;
				}
			break;
			case PS_EndTag:
				if(c == ']') {
					std::string tagname(start, str - start);
					++str;

					if(tagname != root.name)
						throw "Unexpected close tag.";
					return str;
				}
				else {
					++str;
				}
			break;
			default:
				++str;
			break;
		}
	}

	if(state == PS_Text && str != start) {
		BBCode::Tag t;
		t.type = -1;
		t.argument = std::string(start, str - start);
		root.contents.push_back(t);
	}

	return str;
}

void BBCode::parse(const std::string& content) {
	//Clear everything
	root.contents.clear();

	//Start parsing
	parseTag(root, content.c_str());
}

void BBCode::clear() {
	root.contents.clear();
}

BBCode::BBCode() {
}

BBCode::~BBCode() {
}
