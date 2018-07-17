#pragma once
#include "color.h"
#include <string>
#include <vector>
#include <string>
#include <iostream>
#include <istream>
#include <fstream>
#include <sstream>
#include <unordered_map>
#include <functional>
#include <stack>

//Get the equivalent character in different case
char lowercase(char c);
char uppercase(char c);

//Convert a standard string's case
void toLowercase(std::string& str);
void toUppercase(std::string& str);

//Compares c-style strings a and b, ignoring case
//Returns 0 if the strings are equal, the the difference of the first unequal character otherwise
char strcmp_nocase(const char* a, const char* b);

//Compares standard strings a and b, ignoring case
bool streq_nocase(const std::string& a, const std::string& b);
bool streq_nocase(const std::string& str, const std::string& substr, unsigned start, unsigned length = 0);
int strfind_nocase(const std::string& str, const std::string& substr, unsigned start = 0);

//Convert special characters to escape sequences in a string
std::string escape(const std::string& text);

//Convert literal escape sequences in a string
std::string unescape(const std::string& text);

//Escape a case-sensitive string for use on a case-insensitive filesystem
std::string escapeCase(const std::string& text);

//Unescape a case-insensitive filename to a case-sensitive string
std::string unescapeCase(const std::string& text);

//Checks to make sure the string is a valid identifier
bool isIdentifier(const std::string& identifier, const char* extraChars = nullptr);
void makeIdentifier(std::string& identifier, const char* extraChars = nullptr);

//Split a line into Key: Value
bool splitKeyValue(const std::string& input, std::string& key, std::string& value, const char* split = ":");

//Do some basic line parsing operations in addition to splitting
bool parseKeyValue(std::string& input, std::string& key, std::string& value);

//Directly read key-value pairs from a file doing some parsing
bool readKeyValue(std::ifstream& file, std::string& key, std::string& value);

//Iterator that reads key/value pairs and parses includes
struct DataReader {
	struct FilePosition {
		std::ifstream* file;
		std::string filename;
		int line;
	};

	std::stack<FilePosition> files;
	bool allowLines, fullLine, allowMultiline, inMultiline, squash;
	bool skipComments, skipEmpty;
	int indent;
	std::string line;
	std::string key, value;

	DataReader();
	DataReader(const std::string& filename, bool AllowLines = true);
	~DataReader();
	void open(const std::string& filename);
	bool feed(const std::string& line);
	bool handle();
	bool operator++(int);
	std::string position();
};

void skipBOM(std::ifstream& stream);

struct DataHandler {
	struct BlockHandler {
		std::function<bool(std::string&)> openHandler;
		std::function<void()> closeHandler;
		std::unordered_map<std::string, std::function<void(std::string&)>> handlers;
		std::function<void(std::string&)> lineHandlerCB;
		std::function<void(std::string&,std::string&)> defaultHandlerCB;
		std::unordered_map<std::string, BlockHandler*> blocks;

		BlockHandler& block(const std::string& name);
		void openBlock(std::function<bool(std::string&)> cb);
		void closeBlock(std::function<void()> cb);
		void lineHandler(std::function<void(std::string&)> cb);
		void defaultHandler(std::function<void(std::string&, std::string&)> cb);
		void operator()(const std::string& name, std::function<void(std::string&)> cb);

		~BlockHandler();
	};
	DataReader datafile;
	BlockHandler* curHandler;
	int curIndent;

	std::stack<std::pair<BlockHandler*, int>> blockStack;
	BlockHandler defaultBlock;
	std::function<bool(std::string&)> controller;
	DataReader::FilePosition* pos;

	BlockHandler& block(const std::string& name);
	void enterBlock(const std::string& blockName);
	void lineHandler(std::function<void(std::string&)> cb);
	void defaultHandler(std::function<void(std::string&, std::string&)> cb);
	void controlHandler(std::function<bool(std::string&)> cb);
	void operator()(const std::string& name, std::function<void(std::string&)> cb);

	std::string position();
	void feed(const std::string& line);
	void handle();
	void end();

	void read(const std::string& filename);
};

#define HANDLE_BOOL(handler, key, obj, member) handler(key, [&](std::string& value) {\
	if(obj)\
		obj->member = toBool(value);\
});

#define HANDLE_NUM(handler, key, obj, member) handler(key, [&](std::string& value) {\
	if(obj)\
		obj->member = toNumber<decltype(obj->member)>(value);\
});

#define HANDLE_ENUM_W(handler, key, obj, member, Enum, ShowErrors) handler(key, [&](std::string& value) {\
	if(obj) {\
		auto it = Enum.find(value);\
		if(it != Enum.end())\
			obj->member = it->second;\
		else if(ShowErrors)\
			error("Unrecognized " key " '%s'", value.c_str());\
	}\
});

#define HANDLE_ENUM(handler, key, obj, member, Enum) HANDLE_ENUM_W(handler, key, obj, member, Enum, true)

//Generic string split
void split(const std::string& input, std::vector<std::string>& out, char delimit, bool trim = false, bool listEmpty = false);
void split(const std::string& input, std::vector<std::string>& out, const char* delimit, bool trim = false, bool listEmpty = false);

//Splits a string of the format:
// front<delim_front>inner<delim_back>back
//Back is optional
//If both delimeters are not found, returns false and nothing is done to front, inner, or back
//If both delimteres are found, returns true and front, inner, and back are set to the corresponding sub-strings without trimming
bool split(const std::string& input, std::string& front, char delim_front, std::string& inner, char delim_back, std::string* back = 0);

//Split a function call into parts
bool funcSplit(const std::string& input, std::string& name, std::vector<std::string>& arguments, bool strip = true);

//Match a string for a set of expressions with wildcards
typedef std::vector<std::string> CompiledPattern;
void compile_pattern(const char* pattern, CompiledPattern& out);
bool match(const char* name, const char* pattern);
bool match(const char* name, const CompiledPattern& parts);

//Trim whitespace from both ends of the string
std::string trim(const std::string& input);
std::string trim(const std::string& input, const char* trimChars);

//Replace characters in a string
void replaceChar(std::string& str, char replace, char with);
std::string& replace(std::string& str, const std::string& replace, const std::string& with);
std::string replaced(const std::string& str, const std::string& replace, const std::string& with);
std::string& paragraphize(std::string& input, const std::string& parSep, const std::string& lineSep, bool startsParagraph = false);

//Standardize a number into a string representation
std::string standardize(double val, bool showIntegral = false, bool roundUp = false);
std::string formatLargeNum(double val);

//Read number from string
template <class T>
T toNumber(const std::string& str, T def = 0, std::ios_base& (*base)(std::ios_base&) = std::dec) {
	std::istringstream is(str);
	T output;
	if((is >> base >> output).fail())
		return def;
	return output;
}

//Write number to stream
template <class T>
std::string toString(T num, unsigned precision = 0) {
	std::stringstream out;
	out.precision(precision);
	out << std::fixed;
	out << num;
	return out.str();
}

//Write color to string
template<>
std::string toString(Color color, unsigned precision);

//Read color from string, two possible formats: "rrggbbaa", "rr gg bb aa"
//(alpha is optional in both cases)
Color toColor(const std::string& str);

//Read boolean from string
bool toBool(const std::string& str, bool def = false);

//Convert an amount of bytes to a neatly displayed size
std::string toSize(int bytes);

//Convert to a std::string containing a roman numeral representation of numIn;
//Supports numbers up to 999; Appends the result to the given string
void romanNumerals(unsigned int numIn, std::string& romanOut);

//Requires that romanOut points to an array of at least 13 char's
void romanNumerals(unsigned int numIn, char* romanOut);

//Join strings in a vector
std::string join(std::vector<std::string>& list, const char* delimiter = "\n", bool delim_final = true);

//Utilities for manipulating utf-8 text
//Return the char position of the count-th unicode
//character from char position start
int u8pos(const std::string& str, int start, int count = 1);
//Return the unicode character at char position pos
int u8get(const std::string& str, int pos);
//Increments pos to the char position of the next
//unicode character, and sets point to the passed character
void u8next(const std::string& str, int& pos, int& point);
//Decrements pos to the char position of the previous
//unicode character, and sets point to the passed character
void u8prev(const std::string& str, int& pos, int& point);
//Append a unicode code point to a utf-8 string
void u8append(std::string& str, int point);
//Convert unicode code point to four utf-8 chars
int u8(int point);

//Iterator for utf-8
struct u8it {
	const char* str;
	u8it(const std::string& Str);
	u8it(const char* Str);
	int operator++(int);
};
