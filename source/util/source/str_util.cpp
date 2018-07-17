#include "str_util.h"
#include "string.h"
#include <string>
#include <algorithm>

//Get the equivalent character in different case
char lowercase(char c) {
	if(c >= 'A' && c <= 'Z')
		return 'a' + (c - 'A');
	else
		return c;
}

char uppercase(char c) {
	if(c >= 'a' && c <= 'z')
		return 'A' + (c - 'a');
	else
		return c;
}

//Convert a standard string's case
void toLowercase(std::string& str) {
	for(int i = 0, cnt = str.size(); i < cnt; ++i)
		str[i] = lowercase(str[i]);
}

void toUppercase(std::string& str) {
	for(int i = 0, cnt = str.size(); i < cnt; ++i)
		str[i] = uppercase(str[i]);
}

//Compares c-style strings a and b, ignoring case
//Returns 0 if the strings are equal, the the difference of the first unequal character otherwise
char strcmp_nocase(const char* a, const char* b) {
	while(lowercase(*a) == lowercase(*b)) { //TODO: Unicode
		if(*a == 0)
			return 0;
		++a; ++b;
	}

	return *a-*b;
}

bool streq_nocase(const std::string& str, const std::string& substr, unsigned start, unsigned length) {
	if(length == 0)
		length = std::max(substr.size(), str.size());
	if(start + length > str.size())
		return false;
	if(length > substr.size())
		return false;

	const char* a = &str[start];
	const char* b = &substr[0];
	
	while(length > 0) {
		if(lowercase(*a) != lowercase(*b)) //TODO: Unicode
			return false;
		++a; ++b;
		--length;
	}
	return true;
}

int strfind_nocase(const std::string& str, const std::string& substr, unsigned start) {
	unsigned length = substr.size();
	unsigned strsize = str.size();
	if(start + length > strsize)
		return -1;

	unsigned i = start;
	for(; i <= strsize - length; ++i) {
		unsigned j = 0;
		for(; j < length; ++j) {
			if(lowercase(str[i+j]) != lowercase(substr[j]))
				break;
		}

		if(j == length)
			return i;
	}

	return -1;
}

//Convert special characters to escape sequences in a string
std::string escape(const std::string& text) {
	std::string result;
	result.reserve(text.size());

	size_t pos = 0;
	size_t found = text.find_first_of("\n\r\t\\");
	while(found != std::string::npos) {
		if(found - pos > 0)
			result.append(text, pos, found - pos);

		switch(text[found]) {
			case '\n':
				result += "\\n";
			break;
			case '\r':
				result += "\\r";
			break;
			case '\t':
				result += "\\t";
			break;
			case '\\':
				result += "\\\\";
			break;
		}

		pos = found + 1;
		if(pos >= text.size())
			break;
		found = text.find_first_of("\n\r\t\\", pos);
	}

	if(pos < text.size())
		result.append(text, pos, text.size() - pos);

	return result;
}

//Convert literal escape sequences in a string
std::string unescape(const std::string& text) {
	std::string result;
	result.reserve(text.size());

	size_t pos = 0;
	size_t found = text.find('\\');
	while(found != std::string::npos) {
		if(found - pos > 0)
			result.append(text, pos, found - pos);

		if(found >= text.size() - 1)
			break;

		switch(text[found + 1]) {
			case 'n':
				result += '\n';
			break;
			case 'r':
				result += '\r';
			break;
			case 't':
				result += '\t';
			break;
			case '\\':
				result += '\\';
			break;
		}

		pos = found + 2;
		if(pos >= text.size())
			break;
		found = text.find('\\', pos);
	}

	if(pos < text.size())
		result.append(text, pos, text.size() - pos);

	return result;
}

//Escape a case-sensitive string for use on a case-insensitive filesystem
std::string escapeCase(const std::string& text) {
	std::string result;
	result.reserve(text.size());
	for(unsigned i = 0, cnt = text.size(); i < cnt; ++i) {
		char ch = text[i];
		char low = lowercase(ch);

		if(ch == '-') {
			result += "--";
		}
		else if(low != ch) {
			result += "-";
			result += low;
		}
		else {
			result += ch;
		}
	}
	return result;
}

//Unescape a case-insensitive filename to a case-sensitive string
std::string unescapeCase(const std::string& text) {
	std::string result;
	result.reserve(text.size());
	for(unsigned i = 0, cnt = text.size(); i < cnt; ++i) {
		char ch = text[i];

		if(text[i] == '-') {
			if(i == cnt - 1)
				break;
			if(text[i+1] == '-')
				result += "-";
			else
				result += uppercase(text[i+1]);
			++i;
		}
		else {
			result += ch;
		}
	}
	return result;
}

//Checks to make sure the string is a valid identifier
bool isIdentifier(const std::string& identifier, const char* extraChars) {
	if(identifier.empty())
		return false;

	for(auto c = identifier.begin(), end = identifier.end(); c != end; ++c) {
		char chr = *c;

		//Valid characters are 0-9, a-z, A-Z, and '_'
		//Numbers cannot be the first character

		if(chr >= 'a' && chr <= 'z')
			continue;

		if(chr >= 'A' && chr <= 'Z')
			continue;

		if(chr == '_')
			continue;

		if(chr >= '0' && chr <= '9') {
			if(c == identifier.begin())
				return false;
			else
				continue;
		}

		if(extraChars != nullptr) {
			const char* allow = extraChars;
			bool allowed = false;
			while(*allow != '\0') {
				if(*c == chr) {
					allowed = true;
					break;
				}
				++allow;
			}
			if(allowed)
				continue;
		}

		return false;
	}

	return true;
}

void makeIdentifier(std::string& identifier, const char* extraChars) {
	std::string output;
	for(auto c = identifier.begin(), end = identifier.end(); c != end; ++c) {
		char chr = *c;

		//Valid characters are 0-9, a-z, A-Z, and '_'
		//Numbers cannot be the first character

		if(chr >= 'a' && chr <= 'z') {
			output.push_back(chr);
			continue;
		}

		if(chr >= 'A' && chr <= 'Z') {
			output.push_back(chr);
			continue;
		}

		if(chr == '_') {
			output.push_back(chr);
			continue;
		}

		if(chr >= '0' && chr <= '9') {
			if(c == identifier.begin()) {
			}
			else {
				output.push_back(chr);
			}
		}

		if(extraChars != nullptr) {
			const char* allow = extraChars;
			bool allowed = false;
			while(*allow != '\0') {
				if(*c == chr) {
					allowed = true;
					break;
				}
				++allow;
			}
			if(allowed) {
				output.push_back(chr);
				continue;
			}
		}

		if(chr == ' ') {
			output.push_back('_');
			continue;
		}
	}
	identifier = output;
}

//Compares standard strings a and b, ignoring case
bool streq_nocase(const std::string& a, const std::string& b) {
	return strcmp_nocase(a.c_str(), b.c_str()) == 0;
}

//Split a line into Key: Value
bool splitKeyValue(const std::string& input, std::string& key, std::string& value, const char* split) {
	size_t index = input.find(split);
	if(index == std::string::npos)
		return false;
	key = input.substr(0, index);
	value = input.substr(index + 1, input.size() - index - 1);
	return true;
}

//Do some basic line parsing operations in addition to splitting
bool parseKeyValue(std::string& line, std::string& key, std::string& value) {
	line = trim(line);

	if(line.empty())
		return false;

	if(!splitKeyValue(line, key, value))
		return false;

	key = trim(key);
	value = trim(value);

	//Remove quotes
	if(value.size() >= 2 && value.front() == '\"' && value.back() == '\"')
		value = value.substr(1, value.size() - 2);

	return !key.empty();
}

bool readKeyValue(std::ifstream& file, std::string& key, std::string& value) {
	std::string line;

	while(file.is_open() && file.good()) {
		std::getline(file, line);

		if(parseKeyValue(line, key, value))
			return true;
	}
	return false;
}

void skipBOM(std::ifstream& stream) {
	if(!stream.is_open() || !stream.good())
		return;
	if(stream.get() == 0xef) {
		if(stream.get() == 0xbb) {
			if(stream.get() == 0xbf)
				return;
			stream.unget();
		}
		stream.unget();
	}
	stream.unget();
}

//Key/Value reading iterator
DataReader::DataReader()
	: allowLines(true), fullLine(false), allowMultiline(true), indent(0), inMultiline(false), squash(false),
		skipComments(true), skipEmpty(true) {
}

DataReader::DataReader(const std::string& filename, bool AllowLines)
	: allowLines(AllowLines), fullLine(false), allowMultiline(true), indent(0), inMultiline(false), squash(false),
		skipComments(true), skipEmpty(true) {

	files.push(FilePosition());
	files.top().file = new std::ifstream(filename);
	skipBOM(*files.top().file);
	files.top().filename = filename;
	files.top().line = 0;
}

void DataReader::open(const std::string& filename) {
	files.push(FilePosition());
	files.top().file = new std::ifstream(filename);
	skipBOM(*files.top().file);
	files.top().filename = filename;
	files.top().line = 0;
}

DataReader::~DataReader() {
	while(!files.empty()) {
		delete files.top().file;
		files.pop();
	}
}

std::string DataReader::position() {
	return files.top().filename + " | Line " + toString<int>(files.top().line);
}

bool DataReader::feed(const std::string& feedLine) {
	line = feedLine;
	return handle();
}

bool DataReader::handle() {
	//Handle multiline values
	std::string line = this->line;
	if(inMultiline) {
		line = trim(line, "\r\t");

		if(line.size() > 1) {
			if(line[line.size() - 1] == '\\')
				line = line.substr(0, line.size() - 1);
			else
				line += squash ? " " : "\n";
		}
		else {
			//Preserve empty lines in squash mode
			line += squash ? "\n\n" : "\n";
		}

		if(line[0] == '>' && line[1] == '>') {
			//Remove the last linebreak
			if(value.size() > 0 && value[value.size() - 1] == '\n')
				value = value.substr(0, value.size() - 1);
			inMultiline = false;
			return true;
		}
		else {
			value += line;
			return false;
		}
	}

	//Cut off comment
	if(skipComments) {
		auto comment = line.find("//");
		if(comment != line.npos)
			line.resize(comment);
	}

	//Get indent level
	auto pos = line.find_first_not_of("\t\n\r ");
	if(pos == std::string::npos) {
		if(skipEmpty)
			return false;
		indent = 0;
	}
	else {
		if(pos > 0) {
			auto rpos = line.find_last_not_of("\t\n\r ");
			if(rpos != std::string::npos)
				line = line.substr(pos, rpos - pos + 1);
		}
		indent = (int)pos;
	}

	//Detect comments
	if(skipEmpty && line.empty())
		return false;

	bool isKeyValue = splitKeyValue(line, key, value);

	if(!isKeyValue) {
		if(allowLines) {
			fullLine = true;
			return true;
		}
		else {
			return false;
		}
	}
	else {
		key = trim(key);
		value = trim(value);
		fullLine = false;

		//Detect multiline blocks
		if(allowMultiline) {
			if(value == "<<" || value == "<<|") {
				squash = value == "<<|";
				value = "";
				inMultiline = true;
				return false;
			}
		}

		if(!key.empty())
			return true;
		else
			return false;
	}
}

bool DataReader::operator++(int) {
	while(!files.empty()) {
		std::ifstream& file = *files.top().file;
		while(file.is_open() && file.good()) {
			++files.top().line;

			std::getline(file, line);
			line = trim(line, "\n\r");
			if(handle())
				return true;
		}

		delete &file;
		files.pop();
	}

	return false;
}

DataHandler::BlockHandler& DataHandler::BlockHandler::block(const std::string& name) {
	auto* h = new BlockHandler();
	blocks[name] = h;

	return *h;
}

void DataHandler::BlockHandler::openBlock(std::function<bool(std::string&)> cb) {
	openHandler = cb;
}

void DataHandler::BlockHandler::closeBlock(std::function<void()> cb) {
	closeHandler = cb;
}

void DataHandler::BlockHandler::lineHandler(std::function<void(std::string&)> cb) {
	lineHandlerCB = cb;
}

void DataHandler::BlockHandler::defaultHandler(std::function<void(std::string&, std::string&)> cb) {
	defaultHandlerCB = cb;
}

void DataHandler::BlockHandler::operator()(const std::string& name, std::function<void(std::string&)> cb) {
	handlers[name] = cb;
}

DataHandler::BlockHandler& DataHandler::block(const std::string& name) {
	return defaultBlock.block(name);
}

void DataHandler::controlHandler(std::function<bool(std::string&)> cb) {
	controller = cb;
}

void DataHandler::lineHandler(std::function<void(std::string&)> cb) {
	defaultBlock.lineHandler(cb);
}

void DataHandler::defaultHandler(std::function<void(std::string&, std::string&)> cb) {
	defaultBlock.defaultHandler(cb);
}

void DataHandler::operator()(const std::string& name, std::function<void(std::string&)> cb) {
	defaultBlock(name, cb);
}

DataHandler::BlockHandler::~BlockHandler() {
	for(auto it = blocks.begin(), end = blocks.end(); it != end; ++it)
		delete it->second;
}

void DataHandler::feed(const std::string& line) {
	if(datafile.feed(line))
		handle();
}

void DataHandler::enterBlock(const std::string& blockName) {
	auto it = curHandler->blocks.find(blockName);
	if(it != curHandler->blocks.end())
		blockStack.push(std::pair<BlockHandler*,int>(it->second, 0));
}

void DataHandler::handle() {
	if(controller && !controller(datafile.line))
		return;

	if(!blockStack.empty()) {
		curHandler = blockStack.top().first;
		curIndent = blockStack.top().second;

		if(datafile.indent <= curIndent) {
			if(curHandler->closeHandler)
				curHandler->closeHandler();
			if(datafile.files.empty())
				pos = 0;
			else
				pos = &datafile.files.top();
			blockStack.pop();
			handle();
			return;
		}
	}
	else {
		curHandler = &defaultBlock;
		curIndent = 0;
		if(datafile.files.empty())
			pos = 0;
		else
			pos = &datafile.files.top();
	}

	if(datafile.fullLine) {
		if(curHandler->lineHandlerCB)
			curHandler->lineHandlerCB(datafile.line);
	}
	else {
		auto it = curHandler->handlers.find(datafile.key);
		if(it != curHandler->handlers.end()) {
			it->second(datafile.value);
		}
		else {
			auto bit = curHandler->blocks.find(datafile.key);
			if(bit != curHandler->blocks.end()) {
				BlockHandler* handler = bit->second;
				if(handler->openHandler)
					if(!handler->openHandler(datafile.value))
						return;
				blockStack.push(std::pair<BlockHandler*,int>(handler, datafile.indent));
			}
			else if(curHandler->defaultHandlerCB) {
				curHandler->defaultHandlerCB(datafile.key, datafile.value);
			}
			else if(curHandler->lineHandlerCB) {
				curHandler->lineHandlerCB(datafile.line);
			}
		}
	}
}

void DataHandler::end() {
	while(!blockStack.empty()) {
		curHandler = blockStack.top().first;
		if(curHandler->closeHandler)
			curHandler->closeHandler();
		blockStack.pop();
	}
	curHandler = &defaultBlock;
}

void DataHandler::read(const std::string& filename) {
	datafile.open(filename);
	while(datafile++)
		handle();
	end();
}

std::string DataHandler::position() {
	if(pos)
		return pos->filename + " | Line " + toString<int>(pos->line);
	else
		return "--INPUT--";
}

//Generic string split
void split(const std::string& input, std::vector<std::string>& out, char delimit, bool doTrim, bool listEmpty) {
	size_t start = 0;
	size_t size = 0;

	for(unsigned i = 0, cnt = input.size(); i < cnt; ++i) {
		char chr = input[i];
		if(chr == delimit) {
			if(size > 0) {
				if(doTrim)
					out.push_back(trim(input.substr(start, size)));
				else
					out.push_back(input.substr(start, size));
			}
			else if(listEmpty) {
				out.push_back("");
			}
			start = i + 1;
			size = 0;
		}
		else {
			++size;
		}
	}

	if(size > 0) {
		if(doTrim)
			out.push_back(trim(input.substr(start, size)));
		else
			out.push_back(input.substr(start, size));
	}
}

//Generic string split
void split(const std::string& input, std::vector<std::string>& out, const char* delimit, bool doTrim, bool listEmpty) {
	size_t start = 0;
	size_t size = 0;
	int delimLen = strlen(delimit);

	for(unsigned i = 0, cnt = input.size(); i < cnt; ++i) {
		if(i + delimLen <= cnt && strncmp(&input[i], delimit, delimLen) == 0) {
			if(size > 0) {
				if(doTrim)
					out.push_back(trim(input.substr(start, size)));
				else
					out.push_back(input.substr(start, size));
			}
			else if(listEmpty) {
				out.push_back("");
			}
			start = i + delimLen;
			i += delimLen - 1;
			size = 0;
		}
		else {
			++size;
		}
	}

	if(size > 0) {
		if(doTrim)
			out.push_back(trim(input.substr(start, size)));
		else
			out.push_back(input.substr(start, size));
	}
}

//Splits a string of the format:
// front<delim_front>inner<delim_back>back
bool split(const std::string& input, std::string& front, char delim_front, std::string& inner, char delim_back, std::string* back) {
	auto dOne = input.find(delim_front);
	if(dOne == input.npos)
		return false;
	auto dTwo = input.find(delim_back, dOne+1);
	if(dTwo == input.npos)
		return false;

	front = input.substr(0, dOne);
	inner = input.substr(dOne+1,dTwo-(dOne+1));
	if(back)
		*back = input.substr(dTwo+1,input.size()-(dTwo+1));
	return true;
}

//Split a function call into parts
bool funcSplit(const std::string& input, std::string& name, std::vector<std::string>& arguments, bool strip) {
	//First find the function name
	unsigned len = input.size();
	unsigned i = 0, start = 0;
	if(strip) {
		while(input[start] == ' ')
			++start;
	}
	while(input[i] != '(' && i < len)
		++i;

	if(i == len)
		return false;

	//Name is the first part
	name = input.substr(start, i - start);
	++i;

	unsigned depth = 0;
	start = i;
	bool skipWhite = false;

	for(; i < len; ++i) {
		if(skipWhite) {
			if(input[i] == ' ') {
				++start;
				continue;
			}
			else {
				skipWhite = false;
			}
		}

		if(input[i] == '(') {
			++depth;
		}
		else if(input[i] == ')') {
			if(depth == 0) {
				if(i - start > 0)
					arguments.push_back(input.substr(start, i - start));
				return true;
			}
			--depth;
		}
		else if(input[i] == ',' && depth == 0)  {
			if(i - start > 0)
				arguments.push_back(input.substr(start, i - start));
			start = i+1;
			skipWhite = strip;
		}
	}

	return false;
}

//Match a string for a set of expressions with wildcards
void compile_pattern(const char* pattern, std::vector<std::string>& out) {
	std::string filterStr = pattern;

	toLowercase(filterStr);
	if(filterStr.size() == 0)
		return;

	split(filterStr, out, '*');
	if(filterStr[filterStr.size()-1] == '*')
		out.push_back("");
}

bool match(const char* name, const char* pattern) {
	std::vector<std::string> filters;

	compile_pattern(pattern, filters);
	return match(name, filters);
}

bool match(const char* name, const std::vector<std::string>& parts) {
	for(auto part = parts.begin(); part != parts.end(); ++part) {
		if(part->empty())
			continue;
		const char* pStr = strstr(name, part->c_str());
		if(pStr == 0)
			return false;
		name = pStr + part->size();
	}

	if(parts.size() > 0 && parts[parts.size()-1].empty())
		return true;
	else
		return *name == 0;
}


//Replace characters in a string
void replaceChar(std::string& str, char replace, char with) {
	for(int i = 0, cnt = str.size(); i < cnt; ++i)
		if(str[i] == replace)
			str[i] = with;
}

std::string& replace(std::string& str, const std::string& replace, const std::string& with) {
	str = std::move(replaced(str, replace, with));
	return str;
}

std::string replaced(const std::string& input, const std::string& replace, const std::string& with) {
	std::string out;
	size_t at = 0, found = 0;
	while(at < input.size()) {
		found = input.find(replace, at);
		if(found == std::string::npos)
			break;

		if(found >= at) {
			if(found > at)
				out.append(input, at, found-at);
			out.append(with);
		}

		at = found+replace.size();
	}
	if(at < input.size())
		out.append(input, at, input.size() - at);
	return out;
}

std::string& paragraphize(std::string& input, const std::string& parSep, const std::string& lineSep, bool startsParagraph) {
	std::string out;
	size_t at = 0, found = 0;
	if(startsParagraph) {
		found = input.find_first_not_of(" \t");
		if(found < input.size() && input[found] == '\n') {
			size_t second = input.find_first_not_of(" \t", found+1);
			if(second >= input.size() || input[second] != '\n') {
				at = found+1;
			}
		}
	}
	while(at < input.size()) {
		found = input.find('\n', at);
		if(found == std::string::npos)
			break;

		out.append(input, at, found-at);
		if(found > 0 && input[found-1] == '\\') {
			//Nothing here
			found += 1;
		}
		else if(found > 1 && input[found-1] == ' ' && input[found-2] == ' ') {
			out.append(lineSep);
			found += 1;
		}
		else {
			unsigned amount = 1;
			found += 1;
			while(found < input.size() && input[found] == '\n') {
				amount += 1;
				found += 1;
			}
			if(amount == 1) {
				out += ' ';
			}
			else if(amount == 2) {
				out.append(parSep);
			}
			else {
				for(unsigned i = 1; i < amount; ++i)
					out.append(lineSep);
			}
		}
		at = found;
	}
	if(at < input.size())
		out.append(input, at, input.size() - at);
	input = std::move(out);
	return input;
}

//Trim whitespace from both ends of the string
std::string trim(const std::string& input) {
	size_t left = input.find_first_not_of("\t\r\n ");
	size_t right = input.find_last_not_of("\t\r\n ");

	if(left == std::string::npos || right == std::string::npos)
		return "";
	return input.substr(left, right - left + 1);
}

std::string trim(const std::string& input, const char* trimChars) {
	size_t left = input.find_first_not_of(trimChars);
	size_t right = input.find_last_not_of(trimChars);

	if(left == std::string::npos || right == std::string::npos)
		return "";
	return input.substr(left, right - left + 1);
}

template<>
std::string toString<Color>(Color color, unsigned precision) {
	std::string out = "#";

	auto strnibble = [](std::string& str, unsigned char i) {
		if(i < 10)
			str += '0' + i;
		else
			str += 'a' + (i-10);
	};

	auto strbyte = [&strnibble](std::string& str, unsigned char i) {
		unsigned char left = i / 16;
		unsigned char right = i % 16;
		strnibble(str, left);
		strnibble(str, right);
	};

	strbyte(out, color.r);
	strbyte(out, color.g);
	strbyte(out, color.b);
	if(color.a != 0xff)
		strbyte(out, color.a);
	return out;
}

//Read color from string in the following formats: (Alpha is optional and assumed to 255 if missing)
//RGBA
//RRGGBBAA
//RR GG BB AA
#define hexNibble(x) ((x - '0') < 10 ? (x - '0') : ((x - 'A' < 10) ? (x - 'A' + 10) : (x - 'a' + 10)))
Color toColor(const std::string& in) {
	Color out;
	std::string str = in;
	if(str[0] == '#')
		str = str.substr(1, str.size() - 1);

	if(str.find(' ') == std::string::npos) {
		if(str.size() >= 6) {
			out.r = hexNibble(str[0]) << 4 | hexNibble(str[1]);
			out.g = hexNibble(str[2]) << 4 | hexNibble(str[3]);
			out.b = hexNibble(str[4]) << 4 | hexNibble(str[5]);

			if(str.size() >= 8)
				out.a = hexNibble(str[6]) << 4 | hexNibble(str[7]);
		}
		else if(str.size() >= 3) {
			out.r = hexNibble(str[0]) << 4 | hexNibble(str[0]);
			out.g = hexNibble(str[1]) << 4 | hexNibble(str[1]);
			out.b = hexNibble(str[2]) << 4 | hexNibble(str[2]);

			if(str.size() >= 4)
				out.a = hexNibble(str[3]) << 4 | hexNibble(str[3]);
		}
	}
	else {
		std::vector<std::string> elements;
		split(str, elements, ' ');
		
		if(elements.size() >= 3) {
			if(elements[0].size() >= 2)
				out.r = hexNibble(elements[0][0]) << 4 | hexNibble(elements[0][1]);
			if(elements[1].size() >= 2)
				out.g = hexNibble(elements[1][0]) << 4 | hexNibble(elements[1][1]);
			if(elements[2].size() >= 2)
				out.b = hexNibble(elements[2][0]) << 4 | hexNibble(elements[2][1]);

			if(elements.size() >= 4 && elements[3].size() >= 2)
				out.a = hexNibble(elements[3][0]) << 4 | hexNibble(elements[3][1]);
		}
	}

	return out;
}

//Read boolean from string
bool toBool(const std::string& str, bool def) {
	static const std::string strYes("yes"), strNo("no"), strTrue("true"), strFalse("false"), strOn("on"), strOff("off");

	if(streq_nocase(str, strYes) || streq_nocase(str, strTrue) || streq_nocase(str, strOn))
		return true;
	else if(streq_nocase(str, strFalse) || streq_nocase(str, strNo) || streq_nocase(str, strOff))
		return false;
	else if(str.find_first_not_of("0123456789.+-eE") == std::string::npos)
		return toNumber<int>(str) != 0;
	else
		return def;
}

//Convert an amount of bytes to a neatly displayed size
static const char* sizeNames[] = {
	"B",
	"KiB",
	"MiB",
	"GiB",
	"TiB",
	"PiB",
};

std::string toSize(int bytes) {
	unsigned order = 0;
	double frac = bytes;
	while(frac >= 1024.0 && order < 5) {
		frac /= 1024.0;
		++order;
	}

	return toString(frac, 2) + sizeNames[order];
}

//Standardize a number into a string representation
static const char* orderNames[] = {
	"k",
	"M",
	"G",
	"T",
	"P",
	"E",
	"Z",
	"Y",
};

#ifdef _MSC_VER
static inline double round(double x) {
	return floor(x + 0.5);
}
#endif

std::string standardize(double val, bool showIntegral, bool roundUp) {
	unsigned order = 0;
	double frac = val;
	while(frac >= 1000.0 && order < 8) {
		frac /= 1000.0;
		++order;
	}

	unsigned decimals = 0;
	double rounded = frac;
	if(roundUp)
		rounded = ceil(rounded);
	else
		rounded = floor(rounded);

	if(frac < 1) {
		if(showIntegral && fabs(frac - rounded) < 0.01)
			decimals = 0;
		else if(showIntegral && fabs(frac - round(frac)) < 0.0001) {
			decimals = 0;
			frac = round(frac);
		}
		else
			decimals = 2;
	}
	else {
		if(showIntegral && fabs(frac - rounded) < 0.1)
			decimals = 0;
		else if(showIntegral && fabs(frac - round(frac)) < 0.0001) {
			decimals = 0;
			frac = round(frac);
		}
		else
			decimals = 1;
	}

	for(unsigned n = 0; n < decimals; ++n)
		frac *= 10.0;
	if(roundUp)
		frac = ceil(frac);
	else
		frac = floor(frac);
	for(unsigned n = 0; n < decimals; ++n)
		frac /= 10.0;

	if(order > 0)
		return toString(frac, decimals) + orderNames[order-1];
	else
		return toString(frac, decimals);
}

//Convert to a std::string containing a roman numeral representation of numIn;
//Supports numbers up to 999; Appends the result to the given string
void romanNumerals(unsigned int numIn, std::string& romanOut) {
	char romans[16];
	romanNumerals(numIn, romans);

	romanOut += romans;
}

//Requires that romanOut points to an array of at least 13 char's
void romanNumerals(unsigned int numIn, char* romanOut) {
	unsigned char digits[3];
	digits[0] = numIn % 10;
	digits[1] = ((numIn - digits[0]) % 100) / 10;
	digits[2] = ((numIn - digits[1] - digits[0]) % 1000) / 100;

	static const char* romanEquiv[3] = {"IVX","XLC","CDM"};

	for(int i = 2; i >= 0; --i) {
		if(digits[i]) {
			char One = (romanEquiv[i])[0], Five = (romanEquiv[i])[1], Ten = (romanEquiv[i])[2];
			switch(digits[i]) {
				case 1:
					*(romanOut++) = One; break;
				case 2:
					*(romanOut++) = One; *(romanOut++) = One; break;
				case 3:
					*(romanOut++) = One; *(romanOut++) = One; *(romanOut++) = One; break;
				case 4:
					*(romanOut++) = One; *(romanOut++) = Five; break;
				case 5:
					*(romanOut++) = Five; break;
				case 6:
					*(romanOut++) = Five; *(romanOut++) = One; break;
				case 7:
					*(romanOut++) = Five; *(romanOut++) = One; *(romanOut++) = One; break;
				case 8:
					*(romanOut++) = Five; *(romanOut++) = One; *(romanOut++) = One; *(romanOut++) = One; break;
				case 9:
					*(romanOut++) = One; *(romanOut++) = Ten; break;
			}
		}
	}

	*romanOut = '\0';
}

//Join strings in a vector
std::string join(std::vector<std::string>& list, const char* delimiter, bool delim_final) {
	int delim_len = strlen(delimiter);
	int strs = list.size();
	int len = delim_len * (strs - delim_final ? 1 : 0);
	for(int i = 0; i < strs; ++i)
		len += list[i].size();

	std::string contents;
	contents.reserve(len);
	for(int i = 0; i < strs; ++i) {
		contents += list[i];
		if(delim_final || i < strs - 1)
			contents += delimiter;
	}

	return contents;
}

//Convert unicode code point to four utf-8 chars
int u8(int point) {
	if(point < 0x80) {
		return point;
	}
	else if(point < 0x800) {
		int out = 0xC080;
		out |= (point & 0x7C0) << 2;
		out |= (point & 0x3F);
		return out;
	}
	else if(point < 0x1000) {
		int out = 0xE08080;
		out |= (point & 0xF000) << 4;
		out |= (point & 0x0FC0) << 2;
		out |= (point & 0x3F);
		return out;
	}
	else {
		int out = 0xF0808080;
		out |= (point & 0x1C0000) << 6;
		out |= (point & 0x3F000) << 4;
		out |= (point & 0xFC0) << 2;
		out |= (point & 0x3F);
		return out;
	}
}

//Append a unicode code point to a utf-8 string
void u8append(std::string& str, int point) {
	int chars = u8(point);
	char* ch = (char*)&chars;

	str.reserve(str.size() + 4);

	if(ch[3] != 0)
		str += ch[3];
	if(ch[2] != 0)
		str += ch[2];
	if(ch[1] != 0)
		str += ch[1];
	if(ch[0] != 0)
		str += ch[0];
}

//Return the char position of the count-th unicode
//character from char position start
int u8pos(const std::string& str, int start, int count) {
	if(count > 0) {
		while(--count >= 0) {
			unsigned char c = (unsigned char)str[start];

			if(~c & 0x80) {
				start += 1;
			}
			else if((c & 0xC0) && (~c & 0x20)) {
				start += 2;
			}
			else if((c & 0xD0) && (~c & 0x10)) {
				start += 3;
			}
			else if((c & 0xF0) && (~c & 0x08)) {
				start += 4;
			}

			if(start >= (int)str.size())
				return -1;
		}
	}
	else {
		while(++count <= 0) {
			unsigned char c;
			do {
				if(start == 0)
					return -1;

				--start;
				c = (unsigned char)str[start];
			} while((c & 0x80) && (~c & 0x40));
		}
	}

	return start;
}

//Return the unicode character at char position pos
int u8get(const std::string& str, int pos) {
	//Single byte char
	unsigned char c = (unsigned char)str[pos];
	if(~c & 0x80 )
		return c;

	//Two byte char
	if((c & 0xC0) && (~c & 0x20)) {
		unsigned char c2 = (unsigned char)str[pos+1];
		return ((c & 0x1F) << 6)
				| (c2 & 0x3F);
	}

	//Three byte char
	if((c & 0xD0) && (~c & 0x10)) {
		unsigned char c2 = (unsigned char)str[pos+1];
		unsigned char c3 = (unsigned char)str[pos+2];

		return ((c & 0x0F) << 12)
				| ((c2 & 0x3F) << 6)
				| (c3 & 0x3F);
	}

	//Four byte char
	//if((c & 0xF0) && (~c & 0x08)) {
		unsigned char c2 = (unsigned char)str[pos+1];
		unsigned char c3 = (unsigned char)str[pos+2];
		unsigned char c4 = (unsigned char)str[pos+3];

		return ((c & 0x07) << 18)
				| ((c2 & 0x3F) << 12)
				| ((c3 & 0x3F) << 6)
				| (c4 & 0x3F);
	//}
}

//Increments pos to the char position of the count-th
//unicode character, and sets point to the passed character
void u8next(const std::string& str, int& pos, int& point) {
	if(pos < 0 || (size_t)pos >= str.size()) {
		pos = -1;
		return;
	}

	//Read current character
	point = u8get(str, pos);

	//Move position
	pos = u8pos(str, pos, 1);
}

//Decrements pos to the char position of the previous
//unicode character, and sets point to the passed character
void u8prev(const std::string& str, int& pos, int& point) {
	if(pos < 0 || (size_t)pos > str.size()) {
		pos = -1;
		return;
	}

	//Move position
	pos = u8pos(str, pos, -1);

	//Read current character
	if(pos >= 0 && (size_t)pos < str.size())
		point = u8get(str, pos);
}

//Iterator for utf-8
u8it::u8it(const std::string& Str) : str(Str.c_str()) {
}

u8it::u8it(const char* Str) : str(Str) {
}

int u8it::operator++(int) {
	unsigned char c = (unsigned char)*str++;

	//Single byte char
	if(~c & 0x80 )
		return c;

	//Two byte char
	if((c & 0xC0) && (~c & 0x20)) {
		unsigned char c2 = (unsigned char)*str++;
		return ((c & 0x1F) << 6)
				| (c2 & 0x3F);
	}

	//Three byte char
	if((c & 0xD0) && (~c & 0x10)) {
		unsigned char c2 = (unsigned char)*str++;
		unsigned char c3 = (unsigned char)*str++;

		return ((c & 0x0F) << 12)
				| ((c2 & 0x3F) << 6)
				| (c3 & 0x3F);
	}

	//Four byte char
	//if((c & 0xF0) && (~c & 0x08)) {
		unsigned char c2 = (unsigned char)*str++;
		unsigned char c3 = (unsigned char)*str++;
		unsigned char c4 = (unsigned char)*str++;

		return ((c & 0x07) << 18)
				| ((c2 & 0x3F) << 12)
				| ((c3 & 0x3F) << 6)
				| (c4 & 0x3F);
	//}

	//return 0;
}
